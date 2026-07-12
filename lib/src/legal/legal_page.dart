import 'package:flutter/material.dart';

/// Simple scrollable text page used for Terms of Service / Privacy Policy.
/// If [bodyEl] is provided, an EN/ΕΛ language switch is shown in the AppBar
/// (defaulting to English); otherwise the page just shows [body].
class LegalPage extends StatefulWidget {
  const LegalPage({
    super.key,
    required this.title,
    required this.body,
    required this.themeMode,
    this.titleEl,
    this.bodyEl,
  });

  final String title;
  final String body;
  final ThemeMode themeMode;
  final String? titleEl;
  final String? bodyEl;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  var _greek = false;

  @override
  Widget build(BuildContext context) {
    final isLight = widget.themeMode == ThemeMode.light;
    final hasGreek = widget.bodyEl != null;
    final showGreek = hasGreek && _greek;
    final title = showGreek ? (widget.titleEl ?? widget.title) : widget.title;
    final body = showGreek ? widget.bodyEl! : widget.body;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : const Color(0xff121212),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff121212),
        foregroundColor: isLight ? Colors.black : Colors.white,
        elevation: 0,
        title: Text(title),
        actions: hasGreek
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _LanguageSwitch(
                    isGreek: showGreek,
                    isLight: isLight,
                    onChanged: (greek) => setState(() => _greek = greek),
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            body,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({
    required this.isGreek,
    required this.isLight,
    required this.onChanged,
  });

  final bool isGreek;
  final bool isLight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageOption(label: 'EN', selected: !isGreek, onTap: () => onChanged(false)),
          _LanguageOption(label: 'ΕΛ', selected: isGreek, onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff1479ff) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xff8a8a8a),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

const termsOfServiceText = '''
TERMS OF SERVICE / END USER LICENSE AGREEMENT (EULA)
Last Updated: July 2026

By creating an account on Neat ("the App"), you agree to be bound by these Terms. If you do not agree, do not use the App.

1. ELIGIBILITY
You must be at least 13 years old to use Neat. You are responsible for keeping your account login secure.

2. CITY SELECTION & USER RESPONSIBILITY
Neat lets you select a city on a map to view and interact with that local feed. Because this app is public to members of that city, you should not post your precise home address, phone number, or highly private personal routines in public chat fields. You use the application at your own risk regarding information you choose to share.

3. USER-GENERATED CONTENT (UGC) SAFETY MANDATE
In strict compliance with Apple App Store Guideline 1.2, Neat maintains a ZERO-TOLERANCE policy for abusive behavior. You explicitly agree that you will NOT post content that:
• Is hateful, defamatory, or targets individuals or groups maliciously.
• Depicts graphic violence, illegal drugs, or highly dangerous activities.
• Is sexually explicit or pornographic.
• Harasses or bullies other users in the local community.

4. MANDATORY SAFETY CONTROLS (REPORTING & BLOCKING)
To ensure safety, every user has access to immediate tools on the signup/feed screens:
• Report Feature: You can flag any post or user violating these terms. Our moderators review reports within 24 hours.
• Block Feature: You can instantly block any user. Once blocked, they can never see your posts, and their content is permanently hidden from your feed.
• Enforcement: Neat reserves the right to immediately delete objectionable content and ban offending users without notice.

5. TERMINATION
We reserve the right to suspend or terminate your account instantly if you violate these community safety guidelines.

6. CONTACT INFORMATION
To report violations or receive support, please email: neatgreece@gmail.com
''';

const termsOfServiceTitleEl = 'Όροι Χρήσης';

const termsOfServiceTextEl = '''
ΟΡΟΙ ΧΡΗΣΗΣ / ΑΔΕΙΑ ΧΡΗΣΗΣ ΤΕΛΙΚΟΥ ΧΡΗΣΤΗ (EULA)
Τελευταία Ενημέρωση: Ιούλιος 2026

Δημιουργώντας λογαριασμό στο Neat («η Εφαρμογή»), συμφωνείτε να δεσμεύεστε από τους παρόντες Όρους. Εάν δεν συμφωνείτε, μη χρησιμοποιείτε την Εφαρμογή.

1. ΠΡΟΫΠΟΘΕΣΕΙΣ ΣΥΜΜΕΤΟΧΗΣ
Πρέπει να είστε τουλάχιστον 13 ετών για να χρησιμοποιήσετε το Neat. Είστε υπεύθυνοι για τη διατήρηση της ασφάλειας των στοιχείων σύνδεσης του λογαριασμού σας.

2. ΕΠΙΛΟΓΗ ΠΟΛΗΣ & ΕΥΘΥΝΗ ΧΡΗΣΤΗ
Το Neat σάς επιτρέπει να επιλέξετε μια πόλη σε έναν χάρτη για να δείτε και να αλληλεπιδράσετε με την τοπική ροή. Επειδή η εφαρμογή είναι δημόσια προς τα μέλη αυτής της πόλης, δεν θα πρέπει να δημοσιεύετε την ακριβή διεύθυνση κατοικίας σας, τον αριθμό τηλεφώνου σας ή ιδιαίτερα προσωπικές συνήθειες σε δημόσια πεδία συνομιλίας. Χρησιμοποιείτε την εφαρμογή με δική σας ευθύνη όσον αφορά τις πληροφορίες που επιλέγετε να μοιραστείτε.

3. ΥΠΟΧΡΕΩΤΙΚΗ ΠΟΛΙΤΙΚΗ ΑΣΦΑΛΕΙΑΣ ΓΙΑ ΠΕΡΙΕΧΟΜΕΝΟ ΧΡΗΣΤΗ (UGC)
Σε αυστηρή συμμόρφωση με την Οδηγία 1.2 του Apple App Store, το Neat διατηρεί πολιτική ΜΗΔΕΝΙΚΗΣ ΑΝΟΧΗΣ για καταχρηστική συμπεριφορά. Συμφωνείτε ρητά ότι ΔΕΝ θα δημοσιεύσετε περιεχόμενο που:
• Είναι μισαλλόδοξο, συκοφαντικό ή στοχεύει κακόβουλα άτομα ή ομάδες.
• Απεικονίζει βία, παράνομες ουσίες ή εξαιρετικά επικίνδυνες δραστηριότητες.
• Είναι σεξουαλικά ρητό ή πορνογραφικό.
• Παρενοχλεί ή εκφοβίζει άλλους χρήστες της τοπικής κοινότητας.

4. ΥΠΟΧΡΕΩΤΙΚΟΙ ΜΗΧΑΝΙΣΜΟΙ ΑΣΦΑΛΕΙΑΣ (ΑΝΑΦΟΡΑ & ΑΠΟΚΛΕΙΣΜΟΣ)
Για τη διασφάλιση της ασφάλειας, κάθε χρήστης έχει άμεση πρόσβαση σε εργαλεία στις οθόνες εγγραφής/ροής:
• Λειτουργία Αναφοράς: Μπορείτε να επισημάνετε οποιαδήποτε ανάρτηση ή χρήστη που παραβιάζει αυτούς τους όρους. Οι συντονιστές μας εξετάζουν τις αναφορές εντός 24 ωρών.
• Λειτουργία Αποκλεισμού: Μπορείτε να αποκλείσετε άμεσα οποιονδήποτε χρήστη. Μόλις αποκλειστεί, δεν θα μπορεί ποτέ να δει τις αναρτήσεις σας και το περιεχόμενό του θα αποκρύπτεται μόνιμα από τη ροή σας.
• Επιβολή: Το Neat διατηρεί το δικαίωμα να διαγράφει άμεσα απαράδεκτο περιεχόμενο και να αποκλείει παραβάτες χρήστες χωρίς προειδοποίηση.

5. ΤΕΡΜΑΤΙΣΜΟΣ
Διατηρούμε το δικαίωμα να αναστείλουμε ή να τερματίσουμε τον λογαριασμό σας άμεσα εάν παραβιάσετε αυτές τις κατευθυντήριες γραμμές ασφάλειας της κοινότητας.

6. ΣΤΟΙΧΕΙΑ ΕΠΙΚΟΙΝΩΝΙΑΣ
Για να αναφέρετε παραβιάσεις ή να λάβετε υποστήριξη, στείλτε email στο: neatgreece@gmail.com
''';

const privacyPolicyText = '''
PRIVACY POLICY
Last Updated: July 2026

Welcome to Neat ("we," "our," or "us"). Neat is a hyperlocal social media platform designed to connect users with their local city communities. We value your privacy and believe in minimizing data collection. This Privacy Policy outlines how we handle your information.

1. INFORMATION WE DO NOT COLLECT
• We DO NOT collect, log, or track your device's precise GPS location, exact coordinates, or physical street addresses.
• We DO NOT track your background location when the app is closed.

2. INFORMATION WE DO COLLECT
To connect you with your community, we collect:
• Coarse (Approximate) Location Data: Neat operates by city. We provide a map interface where you manually select a city or general region. This city choice is saved to display localized posts and conversations.
• Account Identifiers: Your username, email address, profile picture, and account credentials created during signup.
• User-Generated Content: The text, photos, comments, and posts you choose to share within your selected city's feed.
• Direct Messages: The text, photos, and voice messages you send in private conversations with other users. These are stored to deliver and display your conversation history.
• Push Notification Token: A device identifier used solely to deliver notifications to your device (see Third-Party Services below).
• Diagnostics: Basic crash logs and app performance data to keep Neat running smoothly.

3. THIRD-PARTY SERVICES
Some features are provided by outside services, which process the minimum data needed to make that feature work:
• Firebase Cloud Messaging (Google): delivers push notifications to your device.
• Apple Maps / MapKit: powers map displays for events and locations.
• OpenStreetMap / Nominatim: looks up locations when you search for an address.
• Giphy: powers GIF search inside messages.
These providers only receive what's needed for their specific feature (e.g. a device token, or a location search term) — we do not share your account identifiers, posts, or messages with them beyond that.

4. HOW WE USE YOUR INFORMATION
• To place your profile and posts inside the city feed you selected.
• To authenticate your account and maintain platform safety.
• We DO NOT sell your data, your city choices, or your profile information to third-party advertisers or data brokers.

5. ACCOUNT DELETION & DATA RETENTION
In strict compliance with Apple App Store rules, you can completely erase your footprint at any time:
• You can trigger account deletion instantly from the App Settings / Signup screen by selecting "Delete Account".
• Upon deletion, your personal account identifiers, email, and profile details are permanently purged from our databases within 30 days. Any text posts you made will be completely anonymized and detached from your identity.

6. CONTACT US
For privacy questions, contact us at: neatgreece@gmail.com
''';

const privacyPolicyTitleEl = 'Πολιτική Απορρήτου';

const privacyPolicyTextEl = '''
ΠΟΛΙΤΙΚΗ ΑΠΟΡΡΗΤΟΥ
Τελευταία Ενημέρωση: Ιούλιος 2026

Καλώς ήρθατε στο Neat («εμείς», «μας» ή «η εφαρμογή»). Το Neat είναι μια υπερτοπική πλατφόρμα κοινωνικής δικτύωσης σχεδιασμένη να συνδέει τους χρήστες με την τοπική τους κοινότητα. Δίνουμε μεγάλη σημασία στην ιδιωτικότητά σας και πιστεύουμε στην ελαχιστοποίηση της συλλογής δεδομένων. Αυτή η Πολιτική Απορρήτου περιγράφει πώς διαχειριζόμαστε τα στοιχεία σας.

1. ΠΛΗΡΟΦΟΡΙΕΣ ΠΟΥ ΔΕΝ ΣΥΛΛΕΓΟΥΜΕ
• ΔΕΝ συλλέγουμε, καταγράφουμε ή παρακολουθούμε την ακριβή τοποθεσία GPS της συσκευής σας, τις ακριβείς συντεταγμένες ή τη φυσική σας διεύθυνση.
• ΔΕΝ παρακολουθούμε την τοποθεσία σας στο παρασκήνιο όταν η εφαρμογή είναι κλειστή.

2. ΠΛΗΡΟΦΟΡΙΕΣ ΠΟΥ ΣΥΛΛΕΓΟΥΜΕ
Για να σας συνδέσουμε με την κοινότητά σας, συλλέγουμε:
• Κατά Προσέγγιση Δεδομένα Τοποθεσίας: Το Neat λειτουργεί ανά πόλη. Παρέχουμε μια διεπαφή χάρτη όπου επιλέγετε χειροκίνητα μια πόλη ή γενική περιοχή. Αυτή η επιλογή πόλης αποθηκεύεται για την εμφάνιση τοπικών αναρτήσεων και συνομιλιών.
• Στοιχεία Λογαριασμού: Το όνομα χρήστη, τη διεύθυνση email, τη φωτογραφία προφίλ και τα διαπιστευτήρια λογαριασμού που δημιουργήσατε κατά την εγγραφή.
• Περιεχόμενο Χρήστη: Το κείμενο, τις φωτογραφίες, τα σχόλια και τις αναρτήσεις που επιλέγετε να μοιραστείτε στη ροή της επιλεγμένης πόλης σας.
• Προσωπικά Μηνύματα: Το κείμενο, τις φωτογραφίες και τα φωνητικά μηνύματα που στέλνετε σε ιδιωτικές συνομιλίες με άλλους χρήστες. Αποθηκεύονται για την παράδοση και εμφάνιση του ιστορικού της συνομιλίας σας.
• Διακριτικό Ειδοποιήσεων (Push Token): Ένα αναγνωριστικό συσκευής που χρησιμοποιείται αποκλειστικά για την παράδοση ειδοποιήσεων στη συσκευή σας (δείτε Υπηρεσίες Τρίτων παρακάτω).
• Διαγνωστικά: Βασικά αρχεία καταγραφής σφαλμάτων και δεδομένα απόδοσης της εφαρμογής, ώστε το Neat να λειτουργεί ομαλά.

3. ΥΠΗΡΕΣΙΕΣ ΤΡΙΤΩΝ
Ορισμένες λειτουργίες παρέχονται από εξωτερικές υπηρεσίες, οι οποίες επεξεργάζονται μόνο τα ελάχιστα απαραίτητα δεδομένα για τη λειτουργία τους:
• Firebase Cloud Messaging (Google): παραδίδει ειδοποιήσεις push στη συσκευή σας.
• Apple Maps / MapKit: υποστηρίζει την εμφάνιση χαρτών για εκδηλώσεις και τοποθεσίες.
• OpenStreetMap / Nominatim: αναζητά τοποθεσίες όταν ψάχνετε μια διεύθυνση.
• Giphy: υποστηρίζει την αναζήτηση GIF μέσα στα μηνύματα.
Αυτοί οι πάροχοι λαμβάνουν μόνο ό,τι είναι απαραίτητο για τη συγκεκριμένη λειτουργία τους (π.χ. ένα διακριτικό συσκευής ή έναν όρο αναζήτησης τοποθεσίας) — δεν μοιραζόμαστε τα στοιχεία λογαριασμού, τις αναρτήσεις ή τα μηνύματά σας μαζί τους πέραν αυτού.

4. ΠΩΣ ΧΡΗΣΙΜΟΠΟΙΟΥΜΕ ΤΙΣ ΠΛΗΡΟΦΟΡΙΕΣ ΣΑΣ
• Για να τοποθετήσουμε το προφίλ και τις αναρτήσεις σας μέσα στη ροή της πόλης που επιλέξατε.
• Για την πιστοποίηση του λογαριασμού σας και τη διατήρηση της ασφάλειας της πλατφόρμας.
• ΔΕΝ πουλάμε τα δεδομένα σας, τις επιλογές πόλης σας ή τις πληροφορίες προφίλ σας σε τρίτους διαφημιστές ή μεσίτες δεδομένων.

5. ΔΙΑΓΡΑΦΗ ΛΟΓΑΡΙΑΣΜΟΥ & ΔΙΑΤΗΡΗΣΗ ΔΕΔΟΜΕΝΩΝ
Σε αυστηρή συμμόρφωση με τους κανόνες του Apple App Store, μπορείτε να διαγράψετε πλήρως το ίχνος σας ανά πάσα στιγμή:
• Μπορείτε να ενεργοποιήσετε τη διαγραφή λογαριασμού άμεσα από την οθόνη Ρυθμίσεις εφαρμογής / Εγγραφή, επιλέγοντας «Διαγραφή Λογαριασμού».
• Μετά τη διαγραφή, τα προσωπικά στοιχεία του λογαριασμού σας, το email και τα στοιχεία προφίλ διαγράφονται οριστικά από τις βάσεις δεδομένων μας εντός 30 ημερών. Οποιεσδήποτε αναρτήσεις κειμένου έχετε κάνει θα ανωνυμοποιηθούν πλήρως και θα αποσυνδεθούν από την ταυτότητά σας.

6. ΕΠΙΚΟΙΝΩΝΙΑ ΜΑΖΙ ΜΑΣ
Για ερωτήσεις σχετικά με το απόρρητο, επικοινωνήστε μαζί μας στο: neatgreece@gmail.com
''';
