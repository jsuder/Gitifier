// -------------------------------------------------------
// NewRepositoryDialogController.m
//
// Copyright (c) 2010 Jakub Suder <jakub.suder@gmail.com>
// Licensed under Eclipse Public License v1.0
// -------------------------------------------------------

#import "GrowlController.h"
#import "NewRepositoryDialogController.h"
#import "Repository.h"
#import "RepositoryListController.h"

@implementation NewRepositoryDialogController

@synthesize repositoryListController, repositoryUrlField, label, spinner, addButton, cancelButton;

- (void) awakeFromNib {
  labelText = label.stringValue;
  waitingForSlowClone = NO;
}

- (IBAction) showNewRepositorySheet: (id) sender {
  [repositoryUrlField setStringValue: @""];
  [NSApp beginSheet: [self window]
     modalForWindow: [sender window]
      modalDelegate: nil
     didEndSelector: nil
        contextInfo: nil];
}

- (IBAction) addRepository: (id) sender {
  NSString *url = [[repositoryUrlField stringValue] psTrimmedString];
  if ([url isEqual: @""]) {
    return;
  }

  NSArray *existing = [[repositoryListController repositoryList] valueForKeyPath: @"url"];
  if ([existing indexOfObject: url] != NSNotFound) {
    [self showAlertWithTitle: @"This URL is already on the list."
                     message: @"Try to find something more interesting to monitor..."];
    return;
  }

  editedRepository = [[Repository alloc] initWithUrl: url];
  if (!editedRepository) {
    [self showAlertWithTitle: @"This doesn't look like a git URL."
                     message: @"Please enter a proper git repository address."];
    return;
  }

  [self lockDialog];
  [editedRepository setDelegate: self];
  [editedRepository clone];
  [self setupSlowCloneTimer];
}

- (IBAction) cancelAddingRepository: (id) sender {
  if (editedRepository) {
    [editedRepository cancelCommands];
    [self unlockDialog];
  } else {
    [self hideNewRepositorySheet];
  }
}

- (void) showAlertWithTitle: (NSString *) title message: (NSString *) message {
  NSAlert *alertWindow = [[NSAlert alloc] init];
  [alertWindow addButtonWithTitle: @"OK"];
  [alertWindow setMessageText: title];
  [alertWindow setInformativeText: message];
  [alertWindow beginSheetModalForWindow: self.window
                          modalDelegate: self
                         didEndSelector: @selector(modalWasClosed:)
                            contextInfo: nil];
  [NSApp runModalForWindow: self.window];
}

- (void) modalWasClosed: (NSAlert *) alert {
  [NSApp stopModal];
  [repositoryUrlField becomeFirstResponder];
}

- (void) lockDialog {
  [spinner startAnimation: self];
  [addButton psDisable];
  [repositoryUrlField psDisable];
}

- (void) unlockDialog {
  [spinner stopAnimation: self];
  [addButton psEnable];
  [repositoryUrlField psEnable];
  [self hideSlowCloneWarning];
  [slowCloneTimer invalidate];
  slowCloneTimer = nil;
  editedRepository = nil;
}

- (void) hideNewRepositorySheet {
  [NSApp endSheet: self.window];
  [self.window orderOut: self];
}

- (void) setupSlowCloneTimer {
  slowCloneTimer = [NSTimer scheduledTimerWithTimeInterval: 3.0
                                                    target: self
                                                  selector: @selector(showSlowCloneWarning)
                                                  userInfo: nil
                                                   repeats: NO];
}

- (void) showSlowCloneWarning {
  waitingForSlowClone = YES;
  label.stringValue = @"Please be patient - I'm cloning the repository...";
  label.textColor = [NSColor textColor];
}

- (void) hideSlowCloneWarning {
  waitingForSlowClone = NO;
  label.stringValue = labelText;
  label.textColor = [NSColor disabledControlTextColor];
}

- (void) repositoryWasCloned: (Repository *) repository {
  [repositoryListController addRepository: repository];
  [self hideNewRepositorySheet];

  if (waitingForSlowClone) {
    GrowlController *growl = [GrowlController sharedController];
    [growl showGrowlWithTitle: @"Repository cloned"
                      message: PSFormat(@"Repository at %@ has been successfully added to Gitifier.", repository.url)
                         type: OtherMessageGrowl];
  }

  [self unlockDialog];
}

- (void) repositoryCouldNotBeCloned: (Repository *) repository {
  [self unlockDialog];
  [self showAlertWithTitle: @"Repository could not be cloned."
                   message: @"Make sure you have entered a correct URL."];
}

@end
