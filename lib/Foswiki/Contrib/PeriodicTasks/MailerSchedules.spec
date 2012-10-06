#---++ Mythical mailer
# Task scheduling for the Mythical Mailer
# <BR>
# When MailerContrib is ported to the periodic task framework, it's parameters might come from this file.
#<br>
# **SCHEDULE**
# Not used (yet), prototype debug.
$Foswiki::cfg{MailerSchedule} = '1 15 1-31/3 * Sat 14';
# **BOOLEAN**
# Enables the hypothetical mailer service.
$Foswiki::cfg{Mailer}{Enabled} = 0;
1;
