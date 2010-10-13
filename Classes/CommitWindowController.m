// -------------------------------------------------------
// CommitWindowController.m
//
// Copyright (c) 2010 Jakub Suder <jakub.suder@gmail.com>
// Licensed under MIT license
// -------------------------------------------------------

#import "Commit.h"
#import "CommitWindowController.h"
#import "Git.h"
#import "Repository.h"

#define ERROR_TEXT @"Error loading commit diff."


@implementation CommitWindowController

@synthesize textView, authorLabel, dateLabel, subjectLabel;

- (id) initWithRepository: (Repository *) aRepository commit: (Commit *) aCommit {
  self = [super initWithWindowNibName: @"CommitWindow"];
  if (self) {
    repository = aRepository;
    commit = [aCommit copy];
  }
  return self;
}

- (void) windowDidLoad {
  self.window.title = PSFormat(@"%@ – commit %@", repository.name, commit.gitHash);

  authorLabel.stringValue = PSFormat(@"%@ <%@>", commit.authorName, commit.authorEmail);
  subjectLabel.stringValue = commit.subject;
  dateLabel.stringValue = [commit.date description];

  NSFont *font = [NSFont fontWithName: @"Courier" size: 12.0];
  textView.font = font;

  [self loadCommitDiff];
}

- (void) loadCommitDiff {
  Git *git = [[Git alloc] initWithDelegate: self];
  git.repositoryUrl = repository.url;
  NSString *workingCopy = [repository workingCopyDirectory];

  if (workingCopy && [repository directoryExists: workingCopy]) {
    [git runCommand: @"show" withArguments: PSArray(commit.gitHash, @"--color=never", @"--format=%b") inPath: workingCopy];
  } else {
    [self displayText: ERROR_TEXT];
  }
}

- (void) commandCompleted: (NSString *) command output: (NSString *) output {
  NSString *text = [output psTrimmedString];
  [self handleResult: text];
}

- (void) commandFailed: (NSString *) command output: (NSString *) output {
  [self handleResult: ERROR_TEXT];
}

- (void) handleResult: (NSString *) result {
  [self performSelectorOnMainThread: @selector(displayText:) withObject: result waitUntilDone: NO];
}

- (void) displayText: (NSString *) text {
  textView.string = text;
}

@end