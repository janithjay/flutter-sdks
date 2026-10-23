// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// Default English strings for all ThunderID UI component labels.
const Map<String, String> thunderDefaultStrings = {
  // Actions
  'signIn.button': 'Sign In',
  'signOut.button': 'Sign Out',
  'signUp.button': 'Sign Up',

  // Sign-in form
  'signIn.title': 'Sign In',
  'signIn.username': 'Email or username',
  'signIn.password': 'Password',
  'signIn.submit': 'Continue',
  'signIn.loading': 'Signing in\u2026',
  'signIn.error.generic': 'Sign-in failed. Please try again.',

  // Sign-up form
  'signUp.title': 'Create Account',
  'signUp.submit': 'Create Account',
  'signUp.loading': 'Creating account\u2026',
  'signUp.error.generic': 'Registration failed. Please try again.',

  // Accept invite
  'acceptInvite.title': 'Accept Invitation',
  'acceptInvite.submit': 'Accept',

  // Invite user
  'inviteUser.title': 'Invite User',
  'inviteUser.email': 'Email address',
  'inviteUser.submit': 'Send Invitation',

  // User
  'user.anonymous': 'User',

  // User profile
  'userProfile.title': 'Personal info',
  'userProfile.save': 'Save',
  'userProfile.edit': 'Edit',
  'userProfile.cancel': 'Cancel',
  'userProfile.changePassword': 'Change Password',
  'userProfile.loading': 'Loading profile\u2026',
  'userProfile.error.load': 'Failed to load profile.',
  'userProfile.error.save': 'Failed to save changes.',
  'userProfile.validation.required': 'This field is required.',
  'userProfile.validation.pattern': 'This value is not valid.',
  'userProfile.editDescription': "This information helps us verify it's really you using your account.",

  // Change credential
  'changeCredential.update': 'Update',
  'changeCredential.section': 'Security',
  'changeCredential.heading': 'Change {credential}',
  'changeCredential.description': "Choose a strong {credentialLower} and don't reuse it for other accounts.",
  'changeCredential.new.label': 'New {credential}',
  'changeCredential.confirm.label': 'Confirm New {credential}',
  'changeCredential.mismatch.error': '{credential}s do not match.',
  'changeCredential.requirements.pattern': 'Must match the required format.',
  'changeCredential.generic.error':
      'An error occurred while updating your {credentialLower}. Please try again.',
  'changeCredential.unavailable.description': 'Please contact your administrator.',

  // Organizations
  'organization.unnamed': 'Organization',
  'organizationList.empty': 'No organizations found.',
  'organizationSwitcher.label': 'Switch Organization',
  'organizationSwitcher.current': 'Current',
  'createOrganization.title': 'Create Organization',
  'createOrganization.name': 'Organization name',
  'createOrganization.submit': 'Create',

  // Active sessions
  'activeSessions.section': 'Active sessions',
  'activeSessions.title': 'Your sessions',
  'activeSessions.loading': 'Loading sessions\u2026',
  'activeSessions.empty': 'No active sessions.',
  'activeSessions.manage': 'Manage sessions',
  'activeSessions.footnote': "Sessions are grouped by operating system. Revoke any you don't recognize.",
  'activeSessions.group.one': '1 session on {os}',
  'activeSessions.group.other': '{count} sessions on {os}',
  'activeSessions.device': '{client} on {place}',
  'activeSessions.unknownDevice': 'Unknown device',
  'activeSessions.unknownBrowser': 'Unknown browser',
  'activeSessions.unknown': 'Unknown',
  'activeSessions.current': 'This device',
  'activeSessions.lastActive.since': 'Last active {date}',
  'activeSessions.ip': 'IP address',
  'activeSessions.signedIn': 'Signed in',
  'activeSessions.lastActive': 'Last active',
  'activeSessions.applications': 'Applications',
  'activeSessions.revoke': 'Revoke',
  'activeSessions.revokeOthers': 'Revoke all other sessions',
  'activeSessions.revokeOthers.note': "You'll stay signed in on this device.",
  'activeSessions.current.note': "You're using this session now. To end it, sign out from the app.",
  'activeSessions.confirm.one.title': 'Revoke this session?',
  'activeSessions.confirm.one.body': '{device} will need to sign in again to access your account.',
  'activeSessions.confirm.others.title': 'Revoke other sessions?',
  'activeSessions.confirm.others.body.one':
      "1 other session will be revoked. You'll stay signed in on this device.",
  'activeSessions.confirm.others.body.other':
      "{count} other sessions will be revoked. You'll stay signed in on this device.",
  'activeSessions.cancel': 'Cancel',
  'activeSessions.error.load': 'An error occurred while loading your sessions. Please try again.',
  'activeSessions.error.revoke': 'An error occurred while revoking the session. Please try again.',

  // Language switcher
  'languageSwitcher.label': 'Language',

  // Callback
  'callback.loading': 'Completing sign-in\u2026',
  'callback.error': 'Sign-in could not be completed.',
};
