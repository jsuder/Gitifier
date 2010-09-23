// -------------------------------------------------------
// GitifierAppDelegate.m
//
// Copyright (c) 2010 Jakub Suder <jakub.suder@gmail.com>
// Licensed under MIT license
// -------------------------------------------------------

#import <Growl/GrowlApplicationBridge.h>
#import "RegexKitLite.h"

#import "Commit.h"
#import "Defaults.h"
#import "Git.h"
#import "GitifierAppDelegate.h"
#import "PreferencesWindowController.h"
#import "Repository.h"
#import "RepositoryListController.h"
#import "StatusBarController.h"
#import "Utils.h"

@implementation GitifierAppDelegate

@synthesize monitor, userEmail, preferencesWindowController, statusBarController, repositoryListController,
  repositoryList;

// --- initialization and termination ---

- (void) applicationDidFinishLaunching: (NSNotification *) aNotification {
  repositoryList = [NSMutableArray array];
  [Defaults registerDefaults];
  [GrowlApplicationBridge setGrowlDelegate: (id) @""];

  PSObserve(nil, GitExecutableSetNotification, gitPathUpdated);
  [self loadGitPath];

  [repositoryListController loadRepositories];
  [statusBarController createStatusBarItem];
  [monitor startMonitoring];

  if ([[repositoryListController repositoryList] count] == 0) {
    [self showPreferences: self];
  }
}

// --- actions ---

- (IBAction) showPreferences: (id) sender {
  if (!preferencesWindowController) {
    preferencesWindowController = [[PreferencesWindowController alloc] init];
  }
  [NSApp activateIgnoringOtherApps: YES];
  [preferencesWindowController showWindow: self];
}

- (IBAction) quit: (id) sender {
  // if quit fails because of an open sheet, move the window to front
  [NSApp performSelector: @selector(activateIgnoringOtherApps:)
              withObject: [NSNumber numberWithBool: YES]
              afterDelay: 0.1];
  [NSApp terminate: self];
}

// --- user email management ---

- (void) updateUserEmail {
  if (!userEmail && [Git gitExecutable]) {
    Git *git = [[Git alloc] initWithDelegate: self];
    [git runCommand: @"config" withArguments: PSArray(@"user.email") inPath: NSHomeDirectory()];
  }
}

// --- git path management ---

- (void) loadGitPath {
  NSString *path = [GitifierDefaults objectForKey: GIT_EXECUTABLE_KEY];
  if (path) {
    [Git setGitExecutable: path];
  } else {
    [self findGitPath];
  }
}

- (void) gitPathUpdated {
  [self updateUserEmail];
  [self validateGitPath];
  [GitifierDefaults setObject: [Git gitExecutable] forKey: GIT_EXECUTABLE_KEY];
}

- (void) validateGitPath {
  Git *git = [[Git alloc] initWithDelegate: self];
  [git runCommand: @"version" inPath: NSHomeDirectory()];
}

- (void) findGitPath {
  NSPipe *inputPipe = [NSPipe pipe];
  NSPipe *outputPipe = [NSPipe pipe];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = PSArray(@"--login", @"-c", @"which git");
  task.currentDirectoryPath = NSHomeDirectory();
  task.standardOutput = outputPipe;
  task.standardError = outputPipe;
  task.standardInput = inputPipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *e) {
    NSRunAlertPanel(@"Error: bash not found.",
                    @"Dude, if you don't even have bash, something is seriously wrong...",
                    @"OMG!", nil, nil);
    return;
  }

  NSData *data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] psTrimmedString];

  if (output && (output.length > 0) && (task.terminationStatus == 0)) {
    [Git setGitExecutable: output];
  }
}

- (void) rejectGitPath {
  NSRunAlertPanel(@"Incorrect Git path",
                  PSFormat(@"The file at %@ is not a Git executable.", [Git gitExecutable]),
                  @"OK", nil, nil);
  [Git setGitExecutable: nil];
}

// --- git command callbacks ---

- (void) commandCompleted: (NSString *) command output: (NSString *) output {
  if ([command isEqual: @"config"]) {
    if (output && output.length > 0) {
      userEmail = [output psTrimmedString];
      PSNotifyWithData(UserEmailChangedNotification, PSDict(userEmail, @"email"));
    }
  } else if ([command isEqual: @"version"]) {
    if (!output || ![output isMatchedByRegex: @"^git version \\d"]) {
      [self rejectGitPath];
    }
  }
}

- (void) commandFailed: (NSString *) command output: (NSString *) output {
  if ([command isEqual: @"version"]) {
    [self rejectGitPath];
  }
}

// --- repository callbacks ---

// these should be rare, only when a fetch fails and a repository needs to be recloned

- (void) repositoryWasCloned: (Repository *) repository {
  [repository fetchNewCommits];
}

- (void) repositoryCouldNotBeCloned: (Repository *) repository {
  NSLog(@"Error: repository %@ could not be recloned.", repository.url);
}

// --- Monitor callbacks ---

- (void) commitsReceived: (NSArray *) commits inRepository: (Repository *) repository {
  BOOL ignoreMerges = [GitifierDefaults boolForKey: IGNORE_MERGES_KEY];
  BOOL ignoreOwnCommits = [GitifierDefaults boolForKey: IGNORE_OWN_COMMITS];
  BOOL sticky = [GitifierDefaults boolForKey: STICKY_NOTIFICATIONS_KEY];
  for (Commit *commit in [commits reverseObjectEnumerator]) {
    if (ignoreMerges && [commit isMergeCommit]) {
      return;
    }
    if (ignoreOwnCommits && [commit.authorEmail isEqual: userEmail]) {
      return;
    }
    [GrowlApplicationBridge notifyWithTitle: PSFormat(@"%@ – %@", commit.authorName, repository.name)
                                description: commit.subject
                           notificationName: @"Commit received"
                                   iconData: nil
                                   priority: 0
                                   isSticky: sticky
                               clickContext: nil];
  }
}

@end