import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_el.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('el'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'neat'**
  String get appTitle;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @landingSlogan.
  ///
  /// In en, this message translates to:
  /// **'One app, everything for your city.'**
  String get landingSlogan;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @authAgreePrefix.
  ///
  /// In en, this message translates to:
  /// **'By signing up you agree to our '**
  String get authAgreePrefix;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @authAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get authAnd;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @authAgreeSuffix.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get authAgreeSuffix;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @authSwitchToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authSwitchToSignIn;

  /// No description provided for @authSwitchToSignUp.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get authSwitchToSignUp;

  /// No description provided for @cityPickHint.
  ///
  /// In en, this message translates to:
  /// **'Join the For You of your area by tapping its pin.'**
  String get cityPickHint;

  /// No description provided for @introTitle.
  ///
  /// In en, this message translates to:
  /// **'See what\'s going on in your city'**
  String get introTitle;

  /// No description provided for @introSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Neat only shows posts, news and conversations from your own area.'**
  String get introSubtitle;

  /// No description provided for @introLocalFeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Local feed'**
  String get introLocalFeedTitle;

  /// No description provided for @introLocalFeedBody.
  ///
  /// In en, this message translates to:
  /// **'You see what people near you are posting.'**
  String get introLocalFeedBody;

  /// No description provided for @introEngagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Only in your city'**
  String get introEngagementTitle;

  /// No description provided for @introEngagementBody.
  ///
  /// In en, this message translates to:
  /// **'You post and comment where you live, so conversations stay real.'**
  String get introEngagementBody;

  /// No description provided for @introExploreTitle.
  ///
  /// In en, this message translates to:
  /// **'75+ cities'**
  String get introExploreTitle;

  /// No description provided for @introExploreBody.
  ///
  /// In en, this message translates to:
  /// **'Browse the map and see what\'s happening across Greece.'**
  String get introExploreBody;

  /// No description provided for @introContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get introContinue;

  /// No description provided for @citySetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your city'**
  String get citySetupTitle;

  /// No description provided for @citySetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'It\'s the only city you\'ll be able to take part in.'**
  String get citySetupSubtitle;

  /// No description provided for @citySetupHomeCityTitle.
  ///
  /// In en, this message translates to:
  /// **'This is where you take part'**
  String get citySetupHomeCityTitle;

  /// No description provided for @citySetupHomeCityBody.
  ///
  /// In en, this message translates to:
  /// **'You post, comment and interact only in the city you choose.'**
  String get citySetupHomeCityBody;

  /// No description provided for @citySetupElsewhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Nowhere else'**
  String get citySetupElsewhereTitle;

  /// No description provided for @citySetupElsewhereBody.
  ///
  /// In en, this message translates to:
  /// **'In every other city you can\'t post or comment.'**
  String get citySetupElsewhereBody;

  /// No description provided for @citySetupMicrocopy.
  ///
  /// In en, this message translates to:
  /// **'Choose carefully — you can change city after 6 months.'**
  String get citySetupMicrocopy;

  /// No description provided for @citySetupCta.
  ///
  /// In en, this message translates to:
  /// **'Open the map'**
  String get citySetupCta;

  /// No description provided for @spectatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Spectator Mode'**
  String get spectatorTitle;

  /// No description provided for @spectatorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The map shows you what\'s going on in 75+ cities across Greece.'**
  String get spectatorSubtitle;

  /// No description provided for @spectatorWatchTitle.
  ///
  /// In en, this message translates to:
  /// **'You see everything'**
  String get spectatorWatchTitle;

  /// No description provided for @spectatorWatchBody.
  ///
  /// In en, this message translates to:
  /// **'Posts, news and conversations from any city, without living there.'**
  String get spectatorWatchBody;

  /// No description provided for @spectatorNoInteractionTitle.
  ///
  /// In en, this message translates to:
  /// **'No interaction'**
  String get spectatorNoInteractionTitle;

  /// No description provided for @spectatorNoInteractionBody.
  ///
  /// In en, this message translates to:
  /// **'Outside your own city you can\'t post, comment or react.'**
  String get spectatorNoInteractionBody;

  /// No description provided for @spectatorMicrocopy.
  ///
  /// In en, this message translates to:
  /// **'Your city stays the only place where you take part.'**
  String get spectatorMicrocopy;

  /// No description provided for @spectatorCta.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get spectatorCta;

  /// No description provided for @forgotEnterEmailError.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email or username'**
  String get forgotEnterEmailError;

  /// No description provided for @forgotEnterAllDigits.
  ///
  /// In en, this message translates to:
  /// **'Please enter all 6 digits'**
  String get forgotEnterAllDigits;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get passwordsDontMatch;

  /// No description provided for @forgotEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email or username and we\'ll\nsend a code to your email.'**
  String get forgotEmailSubtitle;

  /// No description provided for @emailOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get emailOrUsername;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkYourEmail;

  /// No description provided for @forgotCodeSentPrefix.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to\n'**
  String get forgotCodeSentPrefix;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @resendCodeIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String resendCodeIn(int seconds);

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @createNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Create new password'**
  String get createNewPassword;

  /// No description provided for @passwordMinHint.
  ///
  /// In en, this message translates to:
  /// **'Must be at least 8 characters.'**
  String get passwordMinHint;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get lightMode;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @blockedAccounts.
  ///
  /// In en, this message translates to:
  /// **'Blocked Accounts'**
  String get blockedAccounts;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirm;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and everything in it — your profile, posts, events, and messages. This action cannot be undone.'**
  String get deleteAccountConfirm;

  /// No description provided for @feedTabFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get feedTabFollowing;

  /// No description provided for @viralOtherCities.
  ///
  /// In en, this message translates to:
  /// **'Other cities'**
  String get viralOtherCities;

  /// No description provided for @noPostsOtherCities.
  ///
  /// In en, this message translates to:
  /// **'No posts in other cities'**
  String get noPostsOtherCities;

  /// No description provided for @deleteAccountTypePrompt.
  ///
  /// In en, this message translates to:
  /// **'To confirm, type {word}'**
  String deleteAccountTypePrompt(String word);

  /// No description provided for @deleteAccountTypeWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get deleteAccountTypeWord;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @actionFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed ({status}): {body}'**
  String actionFailedStatus(int status, String body);

  /// No description provided for @genericErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String genericErrorMessage(String error);

  /// No description provided for @blockedEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t blocked anyone.'**
  String get blockedEmpty;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportTitle;

  /// No description provided for @reportWhyPost.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this post?'**
  String get reportWhyPost;

  /// No description provided for @reportAnonymousNote.
  ///
  /// In en, this message translates to:
  /// **'Your report is anonymous, except if you\'re reporting an intellectual property infringement.'**
  String get reportAnonymousNote;

  /// No description provided for @reportSelectSpecific.
  ///
  /// In en, this message translates to:
  /// **'Select a more specific issue'**
  String get reportSelectSpecific;

  /// No description provided for @reportThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks for letting us know'**
  String get reportThanks;

  /// No description provided for @reportThanksBody.
  ///
  /// In en, this message translates to:
  /// **'We use these reports to show fewer of these things in the future. If someone is in immediate danger, call local emergency services.'**
  String get reportThanksBody;

  /// No description provided for @reportSpam.
  ///
  /// In en, this message translates to:
  /// **'It\'s spam'**
  String get reportSpam;

  /// No description provided for @reportNudity.
  ///
  /// In en, this message translates to:
  /// **'Nudity or sexual activity'**
  String get reportNudity;

  /// No description provided for @reportHateSpeech.
  ///
  /// In en, this message translates to:
  /// **'Hate speech or symbols'**
  String get reportHateSpeech;

  /// No description provided for @reportViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence or dangerous organizations'**
  String get reportViolence;

  /// No description provided for @reportIllegalGoods.
  ///
  /// In en, this message translates to:
  /// **'Sale of illegal or regulated goods'**
  String get reportIllegalGoods;

  /// No description provided for @reportBullying.
  ///
  /// In en, this message translates to:
  /// **'Bullying or harassment'**
  String get reportBullying;

  /// No description provided for @reportIntellectualProperty.
  ///
  /// In en, this message translates to:
  /// **'Intellectual property violation'**
  String get reportIntellectualProperty;

  /// No description provided for @reportSelfInjury.
  ///
  /// In en, this message translates to:
  /// **'Suicide or self-injury'**
  String get reportSelfInjury;

  /// No description provided for @reportEatingDisorders.
  ///
  /// In en, this message translates to:
  /// **'Eating disorders'**
  String get reportEatingDisorders;

  /// No description provided for @reportScam.
  ///
  /// In en, this message translates to:
  /// **'Scam or fraud'**
  String get reportScam;

  /// No description provided for @reportFalseInformation.
  ///
  /// In en, this message translates to:
  /// **'False information'**
  String get reportFalseInformation;

  /// No description provided for @reportDislike.
  ///
  /// In en, this message translates to:
  /// **'I just don\'t like it'**
  String get reportDislike;

  /// No description provided for @reportSubSexualActs.
  ///
  /// In en, this message translates to:
  /// **'Sexual acts'**
  String get reportSubSexualActs;

  /// No description provided for @reportSubGenitals.
  ///
  /// In en, this message translates to:
  /// **'Genitals'**
  String get reportSubGenitals;

  /// No description provided for @reportSubButtocks.
  ///
  /// In en, this message translates to:
  /// **'Buttocks or underwear'**
  String get reportSubButtocks;

  /// No description provided for @reportSubSexualServices.
  ///
  /// In en, this message translates to:
  /// **'Sexual services'**
  String get reportSubSexualServices;

  /// No description provided for @reportSubSuggestiveAccount.
  ///
  /// In en, this message translates to:
  /// **'Suggestive account'**
  String get reportSubSuggestiveAccount;

  /// No description provided for @reportSubRace.
  ///
  /// In en, this message translates to:
  /// **'Race or ethnicity'**
  String get reportSubRace;

  /// No description provided for @reportSubNationalOrigin.
  ///
  /// In en, this message translates to:
  /// **'National origin'**
  String get reportSubNationalOrigin;

  /// No description provided for @reportSubReligion.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get reportSubReligion;

  /// No description provided for @reportSubGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get reportSubGender;

  /// No description provided for @reportSubSexualOrientation.
  ///
  /// In en, this message translates to:
  /// **'Sexual orientation'**
  String get reportSubSexualOrientation;

  /// No description provided for @reportSubDisability.
  ///
  /// In en, this message translates to:
  /// **'Disability or disease'**
  String get reportSubDisability;

  /// No description provided for @reportSubCaste.
  ///
  /// In en, this message translates to:
  /// **'Caste'**
  String get reportSubCaste;

  /// No description provided for @reportSubViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence'**
  String get reportSubViolence;

  /// No description provided for @reportSubWeapons.
  ///
  /// In en, this message translates to:
  /// **'Weapons'**
  String get reportSubWeapons;

  /// No description provided for @reportSubDangerousOrgs.
  ///
  /// In en, this message translates to:
  /// **'Dangerous individuals or organizations'**
  String get reportSubDangerousOrgs;

  /// No description provided for @reportSubChildExploitation.
  ///
  /// In en, this message translates to:
  /// **'Child exploitation'**
  String get reportSubChildExploitation;

  /// No description provided for @reportSubAnimalAbuse.
  ///
  /// In en, this message translates to:
  /// **'Animal abuse'**
  String get reportSubAnimalAbuse;

  /// No description provided for @reportSubDrugs.
  ///
  /// In en, this message translates to:
  /// **'Drugs'**
  String get reportSubDrugs;

  /// No description provided for @reportSubWildlife.
  ///
  /// In en, this message translates to:
  /// **'Endangered wildlife products'**
  String get reportSubWildlife;

  /// No description provided for @reportSubCounterfeit.
  ///
  /// In en, this message translates to:
  /// **'Counterfeit goods'**
  String get reportSubCounterfeit;

  /// No description provided for @reportSubMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get reportSubMe;

  /// No description provided for @reportSubSomeoneIKnow.
  ///
  /// In en, this message translates to:
  /// **'Someone I know'**
  String get reportSubSomeoneIKnow;

  /// No description provided for @reportSubPublicFigure.
  ///
  /// In en, this message translates to:
  /// **'A celebrity or public figure'**
  String get reportSubPublicFigure;

  /// No description provided for @reportSubCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get reportSubCopyright;

  /// No description provided for @reportSubTrademark.
  ///
  /// In en, this message translates to:
  /// **'Trademark'**
  String get reportSubTrademark;

  /// No description provided for @reportSubSelfHarm.
  ///
  /// In en, this message translates to:
  /// **'Suicide or self-harm'**
  String get reportSubSelfHarm;

  /// No description provided for @reportSubDangerousActivities.
  ///
  /// In en, this message translates to:
  /// **'Dangerous activities'**
  String get reportSubDangerousActivities;

  /// No description provided for @reportSubPhishing.
  ///
  /// In en, this message translates to:
  /// **'Phishing or hacked account'**
  String get reportSubPhishing;

  /// No description provided for @reportSubRomanceScam.
  ///
  /// In en, this message translates to:
  /// **'Romance scam'**
  String get reportSubRomanceScam;

  /// No description provided for @reportSubFinancialScam.
  ///
  /// In en, this message translates to:
  /// **'Financial scam'**
  String get reportSubFinancialScam;

  /// No description provided for @reportSubPurchasedFollowers.
  ///
  /// In en, this message translates to:
  /// **'Purchased followers or likes'**
  String get reportSubPurchasedFollowers;

  /// No description provided for @reportSubHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get reportSubHealth;

  /// No description provided for @reportSubPolitics.
  ///
  /// In en, this message translates to:
  /// **'Politics'**
  String get reportSubPolitics;

  /// No description provided for @reportSubSocialIssue.
  ///
  /// In en, this message translates to:
  /// **'Social issue'**
  String get reportSubSocialIssue;

  /// No description provided for @reportSubSomethingElse.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get reportSubSomethingElse;

  /// No description provided for @noMatchesInTown.
  ///
  /// In en, this message translates to:
  /// **'No matches in your town'**
  String get noMatchesInTown;

  /// No description provided for @shareSendTo.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get shareSendTo;

  /// No description provided for @shareSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search people in your city…'**
  String get shareSearchHint;

  /// No description provided for @shareNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get shareNoContacts;

  /// No description provided for @shareNoOneFound.
  ///
  /// In en, this message translates to:
  /// **'No one found in your city'**
  String get shareNoOneFound;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @timeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n}m'**
  String timeMinutes(int n);

  /// No description provided for @timeHours.
  ///
  /// In en, this message translates to:
  /// **'{n}h'**
  String timeHours(int n);

  /// No description provided for @timeDays.
  ///
  /// In en, this message translates to:
  /// **'{n}d'**
  String timeDays(int n);

  /// No description provided for @timeWeeks.
  ///
  /// In en, this message translates to:
  /// **'{n}w'**
  String timeWeeks(int n);

  /// No description provided for @timeMonths.
  ///
  /// In en, this message translates to:
  /// **'{n}mo'**
  String timeMonths(int n);

  /// No description provided for @timeYears.
  ///
  /// In en, this message translates to:
  /// **'{n}y'**
  String timeYears(int n);

  /// No description provided for @likesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load likes.'**
  String get likesLoadError;

  /// No description provided for @noLikesYet.
  ///
  /// In en, this message translates to:
  /// **'No likes yet.'**
  String get noLikesYet;

  /// No description provided for @likesTitle.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get likesTitle;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @followBack.
  ///
  /// In en, this message translates to:
  /// **'Follow Back'**
  String get followBack;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @likedByPrefix.
  ///
  /// In en, this message translates to:
  /// **'Liked by '**
  String get likedByPrefix;

  /// No description provided for @listAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get listAnd;

  /// No description provided for @likedByOthers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} other} other{{count} others}}'**
  String likedByOthers(int count);

  /// No description provided for @pollVotes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 vote} other{{count} votes}}'**
  String pollVotes(int count);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get navCreate;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @postNotFound.
  ///
  /// In en, this message translates to:
  /// **'Post not found'**
  String get postNotFound;

  /// No description provided for @couldNotLoadPost.
  ///
  /// In en, this message translates to:
  /// **'Could not load post'**
  String get couldNotLoadPost;

  /// No description provided for @openInApp.
  ///
  /// In en, this message translates to:
  /// **'Open in app'**
  String get openInApp;

  /// No description provided for @noCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get noCommentsYet;

  /// No description provided for @commentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 comment} other{{count} comments}}'**
  String commentsCount(int count);

  /// No description provided for @newPost.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get newPost;

  /// No description provided for @post.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get post;

  /// No description provided for @pollOptionHint.
  ///
  /// In en, this message translates to:
  /// **'Option {n}'**
  String pollOptionHint(int n);

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File too large. Try a shorter video or smaller photos.'**
  String get fileTooLarge;

  /// No description provided for @uploadTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Upload timed out. Please try again.'**
  String get uploadTimedOut;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please try again.'**
  String get networkError;

  /// No description provided for @photosSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo was too large and skipped. Try selecting a different photo.} other{{count} photos were too large and skipped. Try selecting a different photo.}}'**
  String photosSkipped(int count);

  /// No description provided for @photoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Photo is too large. Try again.'**
  String get photoTooLarge;

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No posts yet.'**
  String get noPostsYet;

  /// No description provided for @deletePost.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get deletePost;

  /// No description provided for @reportPost.
  ///
  /// In en, this message translates to:
  /// **'Report post'**
  String get reportPost;

  /// No description provided for @searchPeopleAndPosts.
  ///
  /// In en, this message translates to:
  /// **'Search people and posts'**
  String get searchPeopleAndPosts;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See more'**
  String get seeMore;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @whoToFollow.
  ///
  /// In en, this message translates to:
  /// **'Who to follow'**
  String get whoToFollow;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get searchPeople;

  /// No description provided for @searchPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get searchPosts;

  /// No description provided for @noResultsFor.
  ///
  /// In en, this message translates to:
  /// **'No results for\n\"{query}\"'**
  String noResultsFor(String query);

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get nothingHereYet;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get tryDifferentSearch;

  /// No description provided for @neatPts.
  ///
  /// In en, this message translates to:
  /// **'{score} neat pts'**
  String neatPts(int score);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get noNotificationsYet;

  /// No description provided for @notifJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just Now'**
  String get notifJustNow;

  /// No description provided for @notifToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get notifToday;

  /// No description provided for @notifLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get notifLast7Days;

  /// No description provided for @notifLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 Days'**
  String get notifLast30Days;

  /// No description provided for @notifOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get notifOlder;

  /// No description provided for @notifLikedPost.
  ///
  /// In en, this message translates to:
  /// **'liked your post'**
  String get notifLikedPost;

  /// No description provided for @notifCommentedPost.
  ///
  /// In en, this message translates to:
  /// **'commented on your post'**
  String get notifCommentedPost;

  /// No description provided for @notifStartedFollowing.
  ///
  /// In en, this message translates to:
  /// **'started following you'**
  String get notifStartedFollowing;

  /// No description provided for @notifRepliedComment.
  ///
  /// In en, this message translates to:
  /// **'replied to your comment'**
  String get notifRepliedComment;

  /// No description provided for @notifLikedComment.
  ///
  /// In en, this message translates to:
  /// **'liked your comment'**
  String get notifLikedComment;

  /// No description provided for @notifMentionedComment.
  ///
  /// In en, this message translates to:
  /// **'mentioned you in a comment'**
  String get notifMentionedComment;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String timeMinutesAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String timeHoursAgo(int n);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String timeDaysAgo(int n);

  /// No description provided for @unpinComment.
  ///
  /// In en, this message translates to:
  /// **'Unpin comment'**
  String get unpinComment;

  /// No description provided for @pinComment.
  ///
  /// In en, this message translates to:
  /// **'Pin comment'**
  String get pinComment;

  /// No description provided for @deleteComment.
  ///
  /// In en, this message translates to:
  /// **'Delete comment'**
  String get deleteComment;

  /// No description provided for @reportComment.
  ///
  /// In en, this message translates to:
  /// **'Report comment'**
  String get reportComment;

  /// No description provided for @pinnedByAuthor.
  ///
  /// In en, this message translates to:
  /// **'Pinned by author'**
  String get pinnedByAuthor;

  /// No description provided for @creator.
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get creator;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @likedByCreator.
  ///
  /// In en, this message translates to:
  /// **'Liked by creator'**
  String get likedByCreator;

  /// No description provided for @commentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commentsTitle;

  /// No description provided for @noCommentsBeFirst.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.\nBe the first!'**
  String get noCommentsBeFirst;

  /// No description provided for @replyToHint.
  ///
  /// In en, this message translates to:
  /// **'Reply to @{username}...'**
  String replyToHint(String username);

  /// No description provided for @addCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Add a comment...'**
  String get addCommentHint;

  /// No description provided for @noInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get noInternet;

  /// No description provided for @noPostsInCity.
  ///
  /// In en, this message translates to:
  /// **'No posts in {city} yet'**
  String noPostsInCity(String city);

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User blocked'**
  String get userBlocked;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked'**
  String get userUnblocked;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block User'**
  String get blockUser;

  /// No description provided for @blockUserConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block @{username}? They won\'t be able to find your profile, see your posts, or message you.'**
  String blockUserConfirm(String username);

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @adminPanel.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanel;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @metricPosts.
  ///
  /// In en, this message translates to:
  /// **'posts'**
  String get metricPosts;

  /// No description provided for @metricFollowers.
  ///
  /// In en, this message translates to:
  /// **'followers'**
  String get metricFollowers;

  /// No description provided for @metricFollowing.
  ///
  /// In en, this message translates to:
  /// **'following'**
  String get metricFollowing;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @noLikedPosts.
  ///
  /// In en, this message translates to:
  /// **'No liked posts yet.'**
  String get noLikedPosts;

  /// No description provided for @noSavedPosts.
  ///
  /// In en, this message translates to:
  /// **'No saved posts yet.'**
  String get noSavedPosts;

  /// No description provided for @followedByPrefix.
  ///
  /// In en, this message translates to:
  /// **'Followed by '**
  String get followedByPrefix;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldBio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get fieldBio;

  /// No description provided for @allowAvatarZoom.
  ///
  /// In en, this message translates to:
  /// **'Allow profile picture zoom'**
  String get allowAvatarZoom;

  /// No description provided for @savedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedTitle;

  /// No description provided for @searchSavedPosts.
  ///
  /// In en, this message translates to:
  /// **'Search saved posts'**
  String get searchSavedPosts;

  /// No description provided for @noResultsShort.
  ///
  /// In en, this message translates to:
  /// **'No results.'**
  String get noResultsShort;

  /// No description provided for @followsYou.
  ///
  /// In en, this message translates to:
  /// **'Follows you'**
  String get followsYou;

  /// No description provided for @sortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get sortDefault;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortNewest;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortOldest;

  /// No description provided for @sortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by '**
  String get sortByLabel;

  /// No description provided for @noUsersYet.
  ///
  /// In en, this message translates to:
  /// **'No users yet.'**
  String get noUsersYet;

  /// No description provided for @followersTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} Followers'**
  String followersTitle(int count);

  /// No description provided for @followingTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} Following'**
  String followingTitle(int count);

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @eventsOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official'**
  String get eventsOfficial;

  /// No description provided for @eventsCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get eventsCommunity;

  /// No description provided for @noEventsYet.
  ///
  /// In en, this message translates to:
  /// **'No events yet.'**
  String get noEventsYet;

  /// No description provided for @sectionLiveToday.
  ///
  /// In en, this message translates to:
  /// **'Live Today'**
  String get sectionLiveToday;

  /// No description provided for @sectionUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Events'**
  String get sectionUpcoming;

  /// No description provided for @sectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other Events'**
  String get sectionOther;

  /// No description provided for @sectionAttended.
  ///
  /// In en, this message translates to:
  /// **'Already Attended'**
  String get sectionAttended;

  /// No description provided for @sectionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed Events'**
  String get sectionCompleted;

  /// No description provided for @catAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catAll;

  /// No description provided for @catMusicConcert.
  ///
  /// In en, this message translates to:
  /// **'Music Concert'**
  String get catMusicConcert;

  /// No description provided for @catLiveConcert.
  ///
  /// In en, this message translates to:
  /// **'Live Concert'**
  String get catLiveConcert;

  /// No description provided for @catSports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get catSports;

  /// No description provided for @catArtCulture.
  ///
  /// In en, this message translates to:
  /// **'Art & Culture'**
  String get catArtCulture;

  /// No description provided for @catFoodDrinks.
  ///
  /// In en, this message translates to:
  /// **'Food & Drinks'**
  String get catFoodDrinks;

  /// No description provided for @catTech.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get catTech;

  /// No description provided for @catComedy.
  ///
  /// In en, this message translates to:
  /// **'Comedy'**
  String get catComedy;

  /// No description provided for @catNetworking.
  ///
  /// In en, this message translates to:
  /// **'Networking'**
  String get catNetworking;

  /// No description provided for @editEvent.
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get editEvent;

  /// No description provided for @deleteEvent.
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get deleteEvent;

  /// No description provided for @reportEvent.
  ///
  /// In en, this message translates to:
  /// **'Report event'**
  String get reportEvent;

  /// No description provided for @buyTickets.
  ///
  /// In en, this message translates to:
  /// **'Buy Tickets'**
  String get buyTickets;

  /// No description provided for @dontAttend.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Attend'**
  String get dontAttend;

  /// No description provided for @attend.
  ///
  /// In en, this message translates to:
  /// **'Attend'**
  String get attend;

  /// No description provided for @createEvent.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get createEvent;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fieldDescription;

  /// No description provided for @officialEvent.
  ///
  /// In en, this message translates to:
  /// **'Official event'**
  String get officialEvent;

  /// No description provided for @hasTicketsLabel.
  ///
  /// In en, this message translates to:
  /// **'Has tickets'**
  String get hasTicketsLabel;

  /// No description provided for @venueRequired.
  ///
  /// In en, this message translates to:
  /// **'Venue / Address (required)'**
  String get venueRequired;

  /// No description provided for @venueOptional.
  ///
  /// In en, this message translates to:
  /// **'Venue / Address (optional)'**
  String get venueOptional;

  /// No description provided for @venueAddress.
  ///
  /// In en, this message translates to:
  /// **'Venue / Address'**
  String get venueAddress;

  /// No description provided for @ticketsUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Tickets website URL (required)'**
  String get ticketsUrlRequired;

  /// No description provided for @ticketsUrl.
  ///
  /// In en, this message translates to:
  /// **'Tickets website URL'**
  String get ticketsUrl;

  /// No description provided for @chooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get chooseDate;

  /// No description provided for @requiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredLabel;

  /// No description provided for @chooseTime.
  ///
  /// In en, this message translates to:
  /// **'Choose time'**
  String get chooseTime;

  /// No description provided for @chooseTimeOptional.
  ///
  /// In en, this message translates to:
  /// **'Choose time (optional)'**
  String get chooseTimeOptional;

  /// No description provided for @photoRequiredOfficial.
  ///
  /// In en, this message translates to:
  /// **'Photo is required for official events'**
  String get photoRequiredOfficial;

  /// No description provided for @photosMakeReal.
  ///
  /// In en, this message translates to:
  /// **'Photos make events feel real'**
  String get photosMakeReal;

  /// No description provided for @tapPhotoReplace.
  ///
  /// In en, this message translates to:
  /// **'Tap photo icon to replace'**
  String get tapPhotoReplace;

  /// No description provided for @pinnedByOrganizer.
  ///
  /// In en, this message translates to:
  /// **'Pinned by organizer'**
  String get pinnedByOrganizer;

  /// No description provided for @couldNotCreateEvent.
  ///
  /// In en, this message translates to:
  /// **'Could not create event ({status}): {body}'**
  String couldNotCreateEvent(int status, String body);

  /// No description provided for @couldNotSaveEvent.
  ///
  /// In en, this message translates to:
  /// **'Could not save event ({status})'**
  String couldNotSaveEvent(int status);

  /// No description provided for @seeIfFriendsGoing.
  ///
  /// In en, this message translates to:
  /// **'See if friends are going'**
  String get seeIfFriendsGoing;

  /// No description provided for @couldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load.'**
  String get couldNotLoad;

  /// No description provided for @noFriendsGoing.
  ///
  /// In en, this message translates to:
  /// **'None of your friends are going yet.'**
  String get noFriendsGoing;

  /// No description provided for @friendsGoing.
  ///
  /// In en, this message translates to:
  /// **'Friends going'**
  String get friendsGoing;

  /// No description provided for @couldNotStartChat.
  ///
  /// In en, this message translates to:
  /// **'Could not start chat'**
  String get couldNotStartChat;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @activeNowHeader.
  ///
  /// In en, this message translates to:
  /// **'Active Now'**
  String get activeNowHeader;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To: '**
  String get toLabel;

  /// No description provided for @suggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get suggested;

  /// No description provided for @noConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get noConnectionTitle;

  /// No description provided for @noConnectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your conversations will appear here once you\'re back online.'**
  String get noConnectionSubtitle;

  /// No description provided for @noResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResultsTitle;

  /// No description provided for @noResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations match your search.'**
  String get noResultsSubtitle;

  /// No description provided for @yourMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your messages'**
  String get yourMessagesTitle;

  /// No description provided for @yourMessagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send a private message to someone in your city.'**
  String get yourMessagesSubtitle;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Message?'**
  String get deleteMessageTitle;

  /// No description provided for @cantBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get cantBeUndone;

  /// No description provided for @unblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock User'**
  String get unblockUser;

  /// No description provided for @blockUserConfirmMsg.
  ///
  /// In en, this message translates to:
  /// **'Block @{name}? They won\'t be able to message you or find your profile or posts, and this conversation will be removed from your inbox.'**
  String blockUserConfirmMsg(String name);

  /// No description provided for @conversationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This conversation is no longer available'**
  String get conversationUnavailable;

  /// No description provided for @editedLabel.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get editedLabel;

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get recording;

  /// No description provided for @sayHi.
  ///
  /// In en, this message translates to:
  /// **'Say hi to start the conversation!'**
  String get sayHi;

  /// No description provided for @pollLabel.
  ///
  /// In en, this message translates to:
  /// **'POLL'**
  String get pollLabel;

  /// No description provided for @editingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get editingMessage;

  /// No description provided for @emojis.
  ///
  /// In en, this message translates to:
  /// **'Emojis'**
  String get emojis;

  /// No description provided for @messageFailedToSend.
  ///
  /// In en, this message translates to:
  /// **'Message failed to send'**
  String get messageFailedToSend;

  /// No description provided for @readLabel.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readLabel;

  /// No description provided for @replyingToUser.
  ///
  /// In en, this message translates to:
  /// **'Replying to @{sender}'**
  String replyingToUser(String sender);

  /// No description provided for @mapMobileOnly.
  ///
  /// In en, this message translates to:
  /// **'Map is available on mobile only.'**
  String get mapMobileOnly;

  /// No description provided for @analyticsTab.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsTab;

  /// No description provided for @securityTab.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityTab;

  /// No description provided for @reportsTab.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTab;

  /// No description provided for @usersTab.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersTab;

  /// No description provided for @adminNoDelete.
  ///
  /// In en, this message translates to:
  /// **'No admin delete available for a {type}'**
  String adminNoDelete(String type);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed ({status})'**
  String deleteFailed(int status);

  /// No description provided for @contentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Content deleted'**
  String get contentDeleted;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noReports.
  ///
  /// In en, this message translates to:
  /// **'No reports'**
  String get noReports;

  /// No description provided for @failedLoadReports.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reports'**
  String get failedLoadReports;

  /// No description provided for @networkErrorShort.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get networkErrorShort;

  /// No description provided for @reportDismissed.
  ///
  /// In en, this message translates to:
  /// **'Report dismissed'**
  String get reportDismissed;

  /// No description provided for @mediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'media unavailable'**
  String get mediaUnavailable;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @deleteTyped.
  ///
  /// In en, this message translates to:
  /// **'Delete {type}'**
  String deleteTyped(String type);

  /// No description provided for @deleteTypedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {type}?'**
  String deleteTypedTitle(String type);

  /// No description provided for @deleteContentConfirm.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the {type} by @{author} and all of its reports.'**
  String deleteContentConfirm(String type, String author);

  /// No description provided for @deleteUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete user?'**
  String get deleteUserTitle;

  /// No description provided for @deleteUserConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete @{username} and all their data.'**
  String deleteUserConfirm(String username);

  /// No description provided for @searchUsersHint.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get searchUsersHint;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @verifyUser.
  ///
  /// In en, this message translates to:
  /// **'Verify user'**
  String get verifyUser;

  /// No description provided for @removeVerification.
  ///
  /// In en, this message translates to:
  /// **'Remove verification'**
  String get removeVerification;

  /// No description provided for @grantOfficialBadge.
  ///
  /// In en, this message translates to:
  /// **'Grant official event badge'**
  String get grantOfficialBadge;

  /// No description provided for @revokeOfficialBadge.
  ///
  /// In en, this message translates to:
  /// **'Revoke official event badge'**
  String get revokeOfficialBadge;

  /// No description provided for @deleteUserTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete user'**
  String get deleteUserTooltip;

  /// No description provided for @adminAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Admin access required'**
  String get adminAccessRequired;

  /// No description provided for @statTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total users'**
  String get statTotalUsers;

  /// No description provided for @statTotalPosts.
  ///
  /// In en, this message translates to:
  /// **'Total posts'**
  String get statTotalPosts;

  /// No description provided for @secActiveUsers.
  ///
  /// In en, this message translates to:
  /// **'Active users'**
  String get secActiveUsers;

  /// No description provided for @statDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get statDaily;

  /// No description provided for @statWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get statWeekly;

  /// No description provided for @statMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get statMonthly;

  /// No description provided for @statStickiness.
  ///
  /// In en, this message translates to:
  /// **'Stickiness'**
  String get statStickiness;

  /// No description provided for @secGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get secGrowth;

  /// No description provided for @statUsersToday.
  ///
  /// In en, this message translates to:
  /// **'Users today'**
  String get statUsersToday;

  /// No description provided for @statPostsToday.
  ///
  /// In en, this message translates to:
  /// **'Posts today'**
  String get statPostsToday;

  /// No description provided for @secLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get secLast30Days;

  /// No description provided for @chartNewUsersPerDay.
  ///
  /// In en, this message translates to:
  /// **'New users per day'**
  String get chartNewUsersPerDay;

  /// No description provided for @chartNewPostsPerDay.
  ///
  /// In en, this message translates to:
  /// **'New posts per day'**
  String get chartNewPostsPerDay;

  /// No description provided for @secEngagement.
  ///
  /// In en, this message translates to:
  /// **'Engagement'**
  String get secEngagement;

  /// No description provided for @statLikesPerPost.
  ///
  /// In en, this message translates to:
  /// **'Likes / post'**
  String get statLikesPerPost;

  /// No description provided for @statCommentsPerPost.
  ///
  /// In en, this message translates to:
  /// **'Comments / post'**
  String get statCommentsPerPost;

  /// No description provided for @statPostsPerUser.
  ///
  /// In en, this message translates to:
  /// **'Posts / user'**
  String get statPostsPerUser;

  /// No description provided for @statCommentsTotal.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get statCommentsTotal;

  /// No description provided for @secTopCities.
  ///
  /// In en, this message translates to:
  /// **'Top cities'**
  String get secTopCities;

  /// No description provided for @secContentSocial.
  ///
  /// In en, this message translates to:
  /// **'Content & social'**
  String get secContentSocial;

  /// No description provided for @statLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get statLikes;

  /// No description provided for @statSaves.
  ///
  /// In en, this message translates to:
  /// **'Saves'**
  String get statSaves;

  /// No description provided for @statFollows.
  ///
  /// In en, this message translates to:
  /// **'Follows'**
  String get statFollows;

  /// No description provided for @statAttending.
  ///
  /// In en, this message translates to:
  /// **'Attending'**
  String get statAttending;

  /// No description provided for @statConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get statConversations;

  /// No description provided for @statMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get statMessages;

  /// No description provided for @statPolls.
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get statPolls;

  /// No description provided for @statPollVotes.
  ///
  /// In en, this message translates to:
  /// **'Poll votes'**
  String get statPollVotes;

  /// No description provided for @statPushDevices.
  ///
  /// In en, this message translates to:
  /// **'Push devices'**
  String get statPushDevices;

  /// No description provided for @statVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get statVerified;

  /// No description provided for @statBlocks.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get statBlocks;

  /// No description provided for @secModeration.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get secModeration;

  /// No description provided for @statOpenReports.
  ///
  /// In en, this message translates to:
  /// **'Open reports'**
  String get statOpenReports;

  /// No description provided for @reviewNeeded.
  ///
  /// In en, this message translates to:
  /// **'to review'**
  String get reviewNeeded;

  /// No description provided for @reviewClear.
  ///
  /// In en, this message translates to:
  /// **'clear'**
  String get reviewClear;

  /// No description provided for @postsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} posts'**
  String postsCountLabel(int count);

  /// No description provided for @cityUsersPosts.
  ///
  /// In en, this message translates to:
  /// **'{users} users · {posts} posts'**
  String cityUsersPosts(int users, int posts);

  /// No description provided for @failedLoadSecurity.
  ///
  /// In en, this message translates to:
  /// **'Failed to load security data'**
  String get failedLoadSecurity;

  /// No description provided for @secLockAccount.
  ///
  /// In en, this message translates to:
  /// **'Lock account'**
  String get secLockAccount;

  /// No description provided for @secUnlockAccount.
  ///
  /// In en, this message translates to:
  /// **'Unlock account'**
  String get secUnlockAccount;

  /// No description provided for @secRevokeSessions.
  ///
  /// In en, this message translates to:
  /// **'Revoke sessions'**
  String get secRevokeSessions;

  /// No description provided for @secActionGeneric.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get secActionGeneric;

  /// No description provided for @secLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get secLock;

  /// No description provided for @secUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get secUnlock;

  /// No description provided for @secRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get secRevoke;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @proceed.
  ///
  /// In en, this message translates to:
  /// **'Proceed?'**
  String get proceed;

  /// No description provided for @secLockBody.
  ///
  /// In en, this message translates to:
  /// **'Disable \"{u}\" and revoke every session/API token. They will be signed out immediately and cannot sign in until unlocked.'**
  String secLockBody(String u);

  /// No description provided for @secUnlockBody.
  ///
  /// In en, this message translates to:
  /// **'Re-enable \"{u}\" so they can sign in again.'**
  String secUnlockBody(String u);

  /// No description provided for @secRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'Sign \"{u}\" out of all devices by revoking every session/API token. The account stays active.'**
  String secRevokeBody(String u);

  /// No description provided for @searchSecurityHint.
  ///
  /// In en, this message translates to:
  /// **'Search actor, IP, path, message…'**
  String get searchSecurityHint;

  /// No description provided for @noEventsMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No events match these filters.'**
  String get noEventsMatchFilters;

  /// No description provided for @chainVerified.
  ///
  /// In en, this message translates to:
  /// **'Chain verified ({checked})'**
  String chainVerified(int checked);

  /// No description provided for @chainBroken.
  ///
  /// In en, this message translates to:
  /// **'Chain broken'**
  String get chainBroken;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'{action} — done'**
  String actionDone(String action);

  /// No description provided for @actionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get actionFailed;

  /// No description provided for @actionFailedStatusShort.
  ///
  /// In en, this message translates to:
  /// **'Action failed ({status})'**
  String actionFailedStatusShort(int status);

  /// No description provided for @auditChainBroken.
  ///
  /// In en, this message translates to:
  /// **'Audit chain broken from entry #{id} — a record was altered or removed outside the application.'**
  String auditChainBroken(String id);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['el', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
