// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'neat';

  @override
  String get signUp => 'Sign up';

  @override
  String get signIn => 'Sign in';

  @override
  String get cancel => 'Cancel';

  @override
  String get landingSlogan => 'One app, everything for your city.';

  @override
  String get username => 'Username';

  @override
  String get email => 'Email';

  @override
  String get fullName => 'Name';

  @override
  String get password => 'Password';

  @override
  String get authAgreePrefix => 'By signing up you agree to our ';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get authAnd => ' and ';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get authAgreeSuffix => '.';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get authSwitchToSignIn => 'Already have an account? Sign in';

  @override
  String get authSwitchToSignUp => 'New here? Create an account';

  @override
  String get cityPickHint =>
      'Join the For You of your area by tapping its pin.';

  @override
  String get introTitle => 'See what\'s going on in your city';

  @override
  String get introSubtitle =>
      'Neat only shows posts, news and conversations from your own area.';

  @override
  String get introLocalFeedTitle => 'Local feed';

  @override
  String get introLocalFeedBody => 'You see what people near you are posting.';

  @override
  String get introEngagementTitle => 'Only in your city';

  @override
  String get introEngagementBody =>
      'You post and comment where you live, so conversations stay real.';

  @override
  String get introExploreTitle => '75+ cities';

  @override
  String get introExploreBody =>
      'Browse the map and see what\'s happening across Greece.';

  @override
  String get introContinue => 'Continue';

  @override
  String get citySetupTitle => 'Choose your city';

  @override
  String get citySetupSubtitle =>
      'The city you choose will be your community on Neat.';

  @override
  String get citySetupHomeCityTitle => 'Your city';

  @override
  String get citySetupHomeCityBody =>
      'This is where you can post, comment and like.';

  @override
  String get citySetupElsewhereTitle => 'Every other city';

  @override
  String get citySetupElsewhereBody =>
      'You can visit them, but you can\'t take part.';

  @override
  String get citySetupMicrocopy =>
      'Choose carefully — you can change city after 1 month.';

  @override
  String get citySetupCta => 'Open the map';

  @override
  String get spectatorTitle => 'Spectator Mode';

  @override
  String get spectatorSubtitle =>
      'See what\'s happening in the rest of Greece\'s cities.';

  @override
  String get spectatorWatchTitle => 'Explore every city';

  @override
  String get spectatorWatchBody =>
      'Posts, Virals and conversations from every corner of Greece.';

  @override
  String get spectatorNoInteractionTitle => 'Visitor only';

  @override
  String get spectatorNoInteractionBody =>
      'You can see everything, but you can\'t post, like or comment.';

  @override
  String get spectatorMicrocopy =>
      'Your city stays the only place where you take part.';

  @override
  String get spectatorCta => 'Continue';

  @override
  String get forgotEnterEmailError => 'Please enter your email or username';

  @override
  String get forgotEnterAllDigits => 'Please enter all 6 digits';

  @override
  String get passwordMinLength => 'Password must be at least 8 characters';

  @override
  String get passwordsDontMatch => 'Passwords don\'t match';

  @override
  String get forgotEmailSubtitle =>
      'Enter your email or username and we\'ll\nsend a code to your email.';

  @override
  String get emailOrUsername => 'Email or username';

  @override
  String get sendCode => 'Send code';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String get forgotCodeSentPrefix => 'We sent a 6-digit code to\n';

  @override
  String get verify => 'Verify';

  @override
  String resendCodeIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get resendCode => 'Resend code';

  @override
  String get createNewPassword => 'Create new password';

  @override
  String get passwordMinHint => 'Must be at least 8 characters.';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get lightMode => 'Light mode';

  @override
  String get legal => 'Legal';

  @override
  String get account => 'Account';

  @override
  String get blockedAccounts => 'Blocked Accounts';

  @override
  String get logOut => 'Log Out';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get logoutConfirm => 'Are you sure you want to log out?';

  @override
  String get deleteAccountConfirm =>
      'This will permanently delete your account and everything in it — your profile, posts, events, and messages. This action cannot be undone.';

  @override
  String get viralOtherCities => 'Other cities';

  @override
  String get noPostsOtherCities => 'No posts in other cities';

  @override
  String deleteAccountTypePrompt(String word) {
    return 'To confirm, type $word';
  }

  @override
  String get deleteAccountTypeWord => 'DELETE';

  @override
  String get delete => 'Delete';

  @override
  String actionFailedStatus(int status, String body) {
    return 'Failed ($status): $body';
  }

  @override
  String genericErrorMessage(String error) {
    return 'Error: $error';
  }

  @override
  String get blockedEmpty => 'You haven\'t blocked anyone.';

  @override
  String get unblock => 'Unblock';

  @override
  String get done => 'Done';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportWhyPost => 'Why are you reporting this post?';

  @override
  String get reportAnonymousNote =>
      'Your report is anonymous, except if you\'re reporting an intellectual property infringement.';

  @override
  String get reportSelectSpecific => 'Select a more specific issue';

  @override
  String get reportThanks => 'Thanks for letting us know';

  @override
  String get reportThanksBody =>
      'We use these reports to show fewer of these things in the future. If someone is in immediate danger, call local emergency services.';

  @override
  String get reportSpam => 'It\'s spam';

  @override
  String get reportNudity => 'Nudity or sexual activity';

  @override
  String get reportHateSpeech => 'Hate speech or symbols';

  @override
  String get reportViolence => 'Violence or dangerous organizations';

  @override
  String get reportIllegalGoods => 'Sale of illegal or regulated goods';

  @override
  String get reportBullying => 'Bullying or harassment';

  @override
  String get reportIntellectualProperty => 'Intellectual property violation';

  @override
  String get reportSelfInjury => 'Suicide or self-injury';

  @override
  String get reportEatingDisorders => 'Eating disorders';

  @override
  String get reportScam => 'Scam or fraud';

  @override
  String get reportFalseInformation => 'False information';

  @override
  String get reportDislike => 'I just don\'t like it';

  @override
  String get reportSubSexualActs => 'Sexual acts';

  @override
  String get reportSubGenitals => 'Genitals';

  @override
  String get reportSubButtocks => 'Buttocks or underwear';

  @override
  String get reportSubSexualServices => 'Sexual services';

  @override
  String get reportSubSuggestiveAccount => 'Suggestive account';

  @override
  String get reportSubRace => 'Race or ethnicity';

  @override
  String get reportSubNationalOrigin => 'National origin';

  @override
  String get reportSubReligion => 'Religion';

  @override
  String get reportSubGender => 'Gender';

  @override
  String get reportSubSexualOrientation => 'Sexual orientation';

  @override
  String get reportSubDisability => 'Disability or disease';

  @override
  String get reportSubCaste => 'Caste';

  @override
  String get reportSubViolence => 'Violence';

  @override
  String get reportSubWeapons => 'Weapons';

  @override
  String get reportSubDangerousOrgs => 'Dangerous individuals or organizations';

  @override
  String get reportSubChildExploitation => 'Child exploitation';

  @override
  String get reportSubAnimalAbuse => 'Animal abuse';

  @override
  String get reportSubDrugs => 'Drugs';

  @override
  String get reportSubWildlife => 'Endangered wildlife products';

  @override
  String get reportSubCounterfeit => 'Counterfeit goods';

  @override
  String get reportSubMe => 'Me';

  @override
  String get reportSubSomeoneIKnow => 'Someone I know';

  @override
  String get reportSubPublicFigure => 'A celebrity or public figure';

  @override
  String get reportSubCopyright => 'Copyright';

  @override
  String get reportSubTrademark => 'Trademark';

  @override
  String get reportSubSelfHarm => 'Suicide or self-harm';

  @override
  String get reportSubDangerousActivities => 'Dangerous activities';

  @override
  String get reportSubPhishing => 'Phishing or hacked account';

  @override
  String get reportSubRomanceScam => 'Romance scam';

  @override
  String get reportSubFinancialScam => 'Financial scam';

  @override
  String get reportSubPurchasedFollowers => 'Purchased followers or likes';

  @override
  String get reportSubHealth => 'Health';

  @override
  String get reportSubPolitics => 'Politics';

  @override
  String get reportSubSocialIssue => 'Social issue';

  @override
  String get reportSubSomethingElse => 'Something else';

  @override
  String get noMatchesInTown => 'No matches in your town';

  @override
  String get shareSendTo => 'Send to';

  @override
  String get shareSearchHint => 'Search people in your city…';

  @override
  String get shareNoContacts => 'No contacts yet';

  @override
  String get shareNoOneFound => 'No one found in your city';

  @override
  String get sent => 'Sent';

  @override
  String get send => 'Send';

  @override
  String get copyLink => 'Copy link';

  @override
  String get justNow => 'just now';

  @override
  String timeMinutes(int n) {
    return '${n}m';
  }

  @override
  String timeHours(int n) {
    return '${n}h';
  }

  @override
  String timeDays(int n) {
    return '${n}d';
  }

  @override
  String timeWeeks(int n) {
    return '${n}w';
  }

  @override
  String timeMonths(int n) {
    return '${n}mo';
  }

  @override
  String timeYears(int n) {
    return '${n}y';
  }

  @override
  String get likesLoadError => 'Could not load likes.';

  @override
  String get noLikesYet => 'No likes yet.';

  @override
  String get likesTitle => 'Likes';

  @override
  String get following => 'Following';

  @override
  String get followBack => 'Follow Back';

  @override
  String get follow => 'Follow';

  @override
  String get likedByPrefix => 'Liked by ';

  @override
  String get listAnd => ' and ';

  @override
  String likedByOthers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count others',
      one: '$count other',
    );
    return '$_temp0';
  }

  @override
  String pollVotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
    );
    return '$_temp0';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navCreate => 'Create';

  @override
  String get navMap => 'Map';

  @override
  String get navProfile => 'Profile';

  @override
  String get postNotFound => 'Post not found';

  @override
  String get couldNotLoadPost => 'Could not load post';

  @override
  String get couldNotOpenLink => 'Could not open the link';

  @override
  String get openInApp => 'Open in app';

  @override
  String get noCommentsYet => 'No comments yet';

  @override
  String commentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments',
      one: '1 comment',
    );
    return '$_temp0';
  }

  @override
  String get newPost => 'New post';

  @override
  String get post => 'Post';

  @override
  String pollOptionHint(int n) {
    return 'Option $n';
  }

  @override
  String get fileTooLarge =>
      'File too large. Try a shorter video or smaller photos.';

  @override
  String get uploadTimedOut => 'Upload timed out. Please try again.';

  @override
  String get networkError => 'Network error. Please try again.';

  @override
  String photosSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count photos were too large and skipped. Try selecting a different photo.',
      one:
          '1 photo was too large and skipped. Try selecting a different photo.',
    );
    return '$_temp0';
  }

  @override
  String get photoTooLarge => 'Photo is too large. Try again.';

  @override
  String videoTooLarge(int size, int max) {
    return 'Video is too large ($size MB). The limit is $max MB — try a shorter clip.';
  }

  @override
  String uploadingVideo(int percent) {
    return 'Uploading video… $percent%';
  }

  @override
  String get couldNotSaveProfile =>
      'Could not save your profile. Check your connection and try again.';

  @override
  String get preparingPhoto => 'Preparing photo…';

  @override
  String get videoProcessing => 'Processing video…';

  @override
  String get postShared => 'Posted';

  @override
  String get postingLabel => 'Posting…';

  @override
  String videoProcessingPercent(int percent) {
    return 'Processing video… $percent%';
  }

  @override
  String get postDeleted => 'This post has been deleted';

  @override
  String get preparingVideo => 'Preparing video…';

  @override
  String get noPostsYet => 'No posts yet.';

  @override
  String get deletePost => 'Delete post';

  @override
  String get reportPost => 'Report post';

  @override
  String get searchPeopleAndPosts => 'Search people and posts';

  @override
  String get seeMore => 'See more';

  @override
  String get clearAll => 'Clear all';

  @override
  String get whoToFollow => 'Who to follow';

  @override
  String get refresh => 'Refresh';

  @override
  String get searchPeople => 'People';

  @override
  String get searchPosts => 'Posts';

  @override
  String noResultsFor(String query) {
    return 'No results for\n\"$query\"';
  }

  @override
  String get nothingHereYet => 'Nothing here yet.';

  @override
  String get tryDifferentSearch => 'Try a different search term.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNotificationsYet => 'No notifications yet.';

  @override
  String get notifJustNow => 'Just Now';

  @override
  String get notifToday => 'Today';

  @override
  String get notifLast7Days => 'Last 7 Days';

  @override
  String get notifLast30Days => 'Last 30 Days';

  @override
  String get notifOlder => 'Older';

  @override
  String get notifLikedPost => 'liked your post';

  @override
  String get notifCommentedPost => 'commented on your post';

  @override
  String get notifStartedFollowing => 'started following you';

  @override
  String get notifRepliedComment => 'replied to your comment';

  @override
  String get notifLikedComment => 'liked your comment';

  @override
  String get notifMentionedComment => 'mentioned you in a comment';

  @override
  String get notifMentionedPost => 'mentioned you in a post';

  @override
  String get notifMentionedDm => 'mentioned you in a DM';

  @override
  String timeMinutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String timeHoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String timeDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String get unpinComment => 'Unpin comment';

  @override
  String get pinComment => 'Pin comment';

  @override
  String get deleteComment => 'Delete comment';

  @override
  String get reportComment => 'Report comment';

  @override
  String get pinnedByAuthor => 'Pinned by author';

  @override
  String get creator => 'Creator';

  @override
  String get reply => 'Reply';

  @override
  String get likedByCreator => 'Liked by creator';

  @override
  String get commentsTitle => 'Comments';

  @override
  String get noCommentsBeFirst => 'No comments yet.\nBe the first!';

  @override
  String replyToHint(String username) {
    return 'Reply to @$username...';
  }

  @override
  String get addCommentHint => 'Add a comment...';

  @override
  String get noInternet => 'No internet connection';

  @override
  String noPostsInCity(String city) {
    return 'No posts in $city yet';
  }

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get userBlocked => 'User blocked';

  @override
  String get userUnblocked => 'User unblocked';

  @override
  String get blockUser => 'Block User';

  @override
  String blockUserConfirm(String username) {
    return 'Block @$username? They won\'t be able to find your profile, see your posts, or message you.';
  }

  @override
  String get block => 'Block';

  @override
  String get adminPanel => 'Admin Panel';

  @override
  String get moreOptions => 'More options';

  @override
  String get metricPosts => 'posts';

  @override
  String get metricFollowers => 'followers';

  @override
  String get metricFollowing => 'following';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get noLikedPosts => 'No liked posts yet.';

  @override
  String get noSavedPosts => 'No saved posts yet.';

  @override
  String get followedByPrefix => 'Followed by ';

  @override
  String get save => 'Save';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldBio => 'Bio';

  @override
  String get allowAvatarZoom => 'Allow profile picture zoom';

  @override
  String get savedTitle => 'Saved';

  @override
  String get searchSavedPosts => 'Search saved posts';

  @override
  String get noResultsShort => 'No results.';

  @override
  String get followsYou => 'Follows you';

  @override
  String get sortDefault => 'Default';

  @override
  String get sortNewest => 'Newest first';

  @override
  String get sortOldest => 'Oldest first';

  @override
  String get sortByLabel => 'Sort by ';

  @override
  String get noUsersYet => 'No users yet.';

  @override
  String followersTitle(int count) {
    return '$count Followers';
  }

  @override
  String followingTitle(int count) {
    return '$count Following';
  }

  @override
  String get city => 'City';

  @override
  String get eventsOfficial => 'Official';

  @override
  String get eventsCommunity => 'Community';

  @override
  String get noEventsYet => 'No events yet.';

  @override
  String get sectionLiveToday => 'Live Today';

  @override
  String get sectionUpcoming => 'Upcoming Events';

  @override
  String get sectionOther => 'Other Events';

  @override
  String get sectionAttended => 'Already Attended';

  @override
  String get sectionCompleted => 'Completed Events';

  @override
  String get catAll => 'All';

  @override
  String get catMusicConcert => 'Music Concert';

  @override
  String get catLiveConcert => 'Live Concert';

  @override
  String get catSports => 'Sports';

  @override
  String get catArtCulture => 'Art & Culture';

  @override
  String get catFoodDrinks => 'Food & Drinks';

  @override
  String get catTech => 'Tech';

  @override
  String get catComedy => 'Comedy';

  @override
  String get catNetworking => 'Networking';

  @override
  String get editEvent => 'Edit event';

  @override
  String get deleteEvent => 'Delete event';

  @override
  String get reportEvent => 'Report event';

  @override
  String get buyTickets => 'Buy Tickets';

  @override
  String get dontAttend => 'Don\'t Attend';

  @override
  String get attend => 'Attend';

  @override
  String get createEvent => 'Create event';

  @override
  String get publish => 'Publish';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldDescription => 'Description';

  @override
  String get officialEvent => 'Official event';

  @override
  String get hasTicketsLabel => 'Has tickets';

  @override
  String get venueRequired => 'Venue / Address (required)';

  @override
  String get venueOptional => 'Venue / Address (optional)';

  @override
  String get venueAddress => 'Venue / Address';

  @override
  String get ticketsUrlRequired => 'Tickets website URL (required)';

  @override
  String get ticketsUrl => 'Tickets website URL';

  @override
  String get chooseDate => 'Choose date';

  @override
  String get requiredLabel => 'Required';

  @override
  String get chooseTime => 'Choose time';

  @override
  String get chooseTimeOptional => 'Choose time (optional)';

  @override
  String get photoRequiredOfficial => 'Photo is required for official events';

  @override
  String get photosMakeReal => 'Photos make events feel real';

  @override
  String get tapPhotoReplace => 'Tap photo icon to replace';

  @override
  String get pinnedByOrganizer => 'Pinned by organizer';

  @override
  String couldNotCreateEvent(int status, String body) {
    return 'Could not create event ($status): $body';
  }

  @override
  String couldNotSaveEvent(int status) {
    return 'Could not save event ($status)';
  }

  @override
  String get seeIfFriendsGoing => 'See if friends are going';

  @override
  String get couldNotLoad => 'Could not load.';

  @override
  String get noFriendsGoing => 'None of your friends are going yet.';

  @override
  String get friendsGoing => 'Friends going';

  @override
  String get couldNotStartChat => 'Could not start chat';

  @override
  String get newMessage => 'New message';

  @override
  String get activeNowHeader => 'Active Now';

  @override
  String get toLabel => 'To: ';

  @override
  String get suggested => 'Suggested';

  @override
  String get noConnectionTitle => 'No connection';

  @override
  String get noConnectionSubtitle =>
      'Your conversations will appear here once you\'re back online.';

  @override
  String get noResultsTitle => 'No results';

  @override
  String get noResultsSubtitle => 'No conversations match your search.';

  @override
  String get yourMessagesTitle => 'Your messages';

  @override
  String get yourMessagesSubtitle =>
      'Send a private message to someone in your city.';

  @override
  String get copy => 'Copy';

  @override
  String get messageCopied => 'Message copied';

  @override
  String get edit => 'Edit';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get report => 'Report';

  @override
  String get deleteMessageTitle => 'Delete Message?';

  @override
  String get cantBeUndone => 'This can\'t be undone.';

  @override
  String get unblockUser => 'Unblock User';

  @override
  String blockUserConfirmMsg(String name) {
    return 'Block @$name? They won\'t be able to message you or find your profile or posts, and this conversation will be removed from your inbox.';
  }

  @override
  String get conversationUnavailable =>
      'This conversation is no longer available';

  @override
  String get editedLabel => 'Edited';

  @override
  String get recording => 'Recording...';

  @override
  String get sayHi => 'Say hi to start the conversation!';

  @override
  String get pollLabel => 'POLL';

  @override
  String get editingMessage => 'Editing message';

  @override
  String get emojis => 'Emojis';

  @override
  String get messageFailedToSend => 'Message failed to send';

  @override
  String get readLabel => 'Read';

  @override
  String replyingToUser(String sender) {
    return 'Replying to @$sender';
  }

  @override
  String get mapMobileOnly => 'Map is available on mobile only.';

  @override
  String get analyticsTab => 'Analytics';

  @override
  String get securityTab => 'Security';

  @override
  String get reportsTab => 'Reports';

  @override
  String get usersTab => 'Users';

  @override
  String adminNoDelete(String type) {
    return 'No admin delete available for a $type';
  }

  @override
  String deleteFailed(int status) {
    return 'Delete failed ($status)';
  }

  @override
  String get contentDeleted => 'Content deleted';

  @override
  String get retry => 'Retry';

  @override
  String get noReports => 'No reports';

  @override
  String get failedLoadReports => 'Failed to load reports';

  @override
  String get networkErrorShort => 'Network error';

  @override
  String get reportDismissed => 'Report dismissed';

  @override
  String get mediaUnavailable => 'media unavailable';

  @override
  String get dismiss => 'Dismiss';

  @override
  String deleteTyped(String type) {
    return 'Delete $type';
  }

  @override
  String deleteTypedTitle(String type) {
    return 'Delete $type?';
  }

  @override
  String deleteContentConfirm(String type, String author) {
    return 'This permanently deletes the $type by @$author and all of its reports.';
  }

  @override
  String get deleteUserTitle => 'Delete user?';

  @override
  String deleteUserConfirm(String username) {
    return 'This will permanently delete @$username and all their data.';
  }

  @override
  String get searchUsersHint => 'Search users...';

  @override
  String get noUsersFound => 'No users found';

  @override
  String get verifyUser => 'Verify user';

  @override
  String get removeVerification => 'Remove verification';

  @override
  String get grantOfficialBadge => 'Grant official event badge';

  @override
  String get revokeOfficialBadge => 'Revoke official event badge';

  @override
  String get deleteUserTooltip => 'Delete user';

  @override
  String get adminAccessRequired => 'Admin access required';

  @override
  String get statTotalUsers => 'Total users';

  @override
  String get statTotalPosts => 'Total posts';

  @override
  String get secActiveUsers => 'Active users';

  @override
  String get statDaily => 'Daily';

  @override
  String get statWeekly => 'Weekly';

  @override
  String get statMonthly => 'Monthly';

  @override
  String get statStickiness => 'Stickiness';

  @override
  String get secGrowth => 'Growth';

  @override
  String get statUsersToday => 'Users today';

  @override
  String get statPostsToday => 'Posts today';

  @override
  String get secLast30Days => 'Last 30 days';

  @override
  String get chartNewUsersPerDay => 'New users per day';

  @override
  String get chartNewPostsPerDay => 'New posts per day';

  @override
  String get secEngagement => 'Engagement';

  @override
  String get statLikesPerPost => 'Likes / post';

  @override
  String get statCommentsPerPost => 'Comments / post';

  @override
  String get statPostsPerUser => 'Posts / user';

  @override
  String get statCommentsTotal => 'Comments';

  @override
  String get secTopCities => 'Top cities';

  @override
  String get secContentSocial => 'Content & social';

  @override
  String get statLikes => 'Likes';

  @override
  String get statSaves => 'Saves';

  @override
  String get statFollows => 'Follows';

  @override
  String get statAttending => 'Attending';

  @override
  String get statConversations => 'Conversations';

  @override
  String get statMessages => 'Messages';

  @override
  String get statPolls => 'Polls';

  @override
  String get statPollVotes => 'Poll votes';

  @override
  String get statPushDevices => 'Push devices';

  @override
  String get statVerified => 'Verified';

  @override
  String get statBlocks => 'Blocks';

  @override
  String get secModeration => 'Moderation';

  @override
  String get statOpenReports => 'Open reports';

  @override
  String get reviewNeeded => 'to review';

  @override
  String get reviewClear => 'clear';

  @override
  String postsCountLabel(int count) {
    return '$count posts';
  }

  @override
  String cityUsersPosts(int users, int posts) {
    return '$users users · $posts posts';
  }

  @override
  String get failedLoadSecurity => 'Failed to load security data';

  @override
  String get secLockAccount => 'Lock account';

  @override
  String get secUnlockAccount => 'Unlock account';

  @override
  String get secRevokeSessions => 'Revoke sessions';

  @override
  String get secActionGeneric => 'Action';

  @override
  String get secLock => 'Lock';

  @override
  String get secUnlock => 'Unlock';

  @override
  String get secRevoke => 'Revoke';

  @override
  String get confirm => 'Confirm';

  @override
  String get proceed => 'Proceed?';

  @override
  String secLockBody(String u) {
    return 'Disable \"$u\" and revoke every session/API token. They will be signed out immediately and cannot sign in until unlocked.';
  }

  @override
  String secUnlockBody(String u) {
    return 'Re-enable \"$u\" so they can sign in again.';
  }

  @override
  String secRevokeBody(String u) {
    return 'Sign \"$u\" out of all devices by revoking every session/API token. The account stays active.';
  }

  @override
  String get searchSecurityHint => 'Search actor, IP, path, message…';

  @override
  String get noEventsMatchFilters => 'No events match these filters.';

  @override
  String chainVerified(int checked) {
    return 'Chain verified ($checked)';
  }

  @override
  String get chainBroken => 'Chain broken';

  @override
  String actionDone(String action) {
    return '$action — done';
  }

  @override
  String get actionFailed => 'Action failed';

  @override
  String actionFailedStatusShort(int status) {
    return 'Action failed ($status)';
  }

  @override
  String auditChainBroken(String id) {
    return 'Audit chain broken from entry #$id — a record was altered or removed outside the application.';
  }

  @override
  String get reactionsTitle => 'Reactions';

  @override
  String get tapToRemoveReaction => 'Tap to remove';

  @override
  String get addBio => 'Add bio';

  @override
  String joiningCity(String city) {
    return 'Joining $city...';
  }

  @override
  String returningToCity(String city) {
    return 'Returning to $city...';
  }

  @override
  String get neatPass => 'Neat Pass';

  @override
  String get neatPoints => 'Neat Points';

  @override
  String get neatPassHowToEarn =>
      'Appear in the Virals top-10 to earn Neat Points.';

  @override
  String get neatPassCurrentPoints => 'Points Balance';

  @override
  String get photoViewOnce => 'View once';

  @override
  String get photoAllowReplay => 'Allow replay';

  @override
  String get photoKeepInChat => 'Keep in chat';

  @override
  String get photoLabel => 'Photo';

  @override
  String get photoTapToView => 'Tap to view';

  @override
  String get photoReplay => 'Replay';

  @override
  String get photoOpened => 'Opened';

  @override
  String get photoSentOnce => 'Sent · View once';

  @override
  String get photoSentReplay => 'Sent · Allow replay';

  @override
  String get photoUnavailable => 'This photo is no longer available';

  @override
  String get signUpMethodTitle => 'Create your account';

  @override
  String get signUpMethodSubtitle =>
      'Pick how you want to sign up. You can always sign in the same way later.';

  @override
  String get signUpWithApple => 'Continue with Apple';

  @override
  String get signUpWithGoogle => 'Continue with Google';

  @override
  String get signUpWithEmail => 'Sign up with email';

  @override
  String get signUpMethodHaveAccount => 'Already have an account?';

  @override
  String get signUpMethodSignIn => 'Sign in';

  @override
  String get signUpGoogleUnavailable => 'Google sign-in is not set up yet.';

  @override
  String get usernameSetupTitle => 'Pick your username';

  @override
  String get usernameSetupSubtitle =>
      'This is how people find you and mention you. You can change it later in your profile.';

  @override
  String get usernameSetupHint => 'username';

  @override
  String get usernameSetupRules =>
      'Letters, numbers, dots and underscores. 3–20 characters.';

  @override
  String get usernameSetupCta => 'Continue';

  @override
  String get usernameSetupTaken => 'That username is already taken.';

  @override
  String get usernameSetupTooShort => 'Username must be at least 3 characters.';

  @override
  String get usernameSetupTooLong => 'Username must be at most 20 characters.';

  @override
  String get usernameSetupBadChars =>
      'Only letters, numbers, dots and underscores.';

  @override
  String get authOr => 'or';

  @override
  String get setPasswordTitle => 'Set a password';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get setPasswordExplain =>
      'You signed up with Apple or Google, so your account has no password yet. Adding one gives you a second way to sign in if you ever lose access to that account.';

  @override
  String get changePasswordExplain => 'Choose a new password for your account.';

  @override
  String get currentPasswordHint => 'Current password';

  @override
  String get newPasswordHint => 'New password';

  @override
  String get confirmPasswordHint => 'Repeat new password';

  @override
  String get passwordsDoNotMatch => 'The two passwords are not the same.';

  @override
  String get passwordSaved => 'Password saved.';

  @override
  String get savePassword => 'Save';

  @override
  String get support => 'Support';

  @override
  String cityChangeLocked(String date) {
    return 'You can change your city again on $date.';
  }

  @override
  String get cityChangeHint =>
      'Tap to change. You can change your city once a month.';
}
