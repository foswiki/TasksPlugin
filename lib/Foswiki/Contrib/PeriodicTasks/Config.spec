# ---+ Periodic Tasks
# Settings for periodic task scheduler
# <P>
# TWiki performs background maintenance tasks using a system daemon.
# <P>Specify the schedules on which you want these tasks run, using
# the time spec portion of vixie-cron <b><i>crontab</i></b> format.  <br />You may find more documentation
# of this format using <b><i>man 5 crontab</i></b> on a unix/linux system.
# <p> Although crontab format is used, the fields are displayed in a more intuitive order here.
#<p>
# Summary:<br />
# When the current date and time match these fields, the task will be run.
# <br /><ul>
#  <li>Minute, Hour, DayofMonth, Month, DayofWeek
#  <li> An asterisk( '*' ) means any value matches a field.  
#  <li> More than one value can match; select with control/click.
#  <li> s-e means start thru end, inclusive.  s-e/i means every i units from s thru e, inclusive.
#</ul>Crontab's abbreviated formats are expanded into the GUI listboxes, and are condensed during save.
# <br>Note: do not specify '*' with any other value in the same field.  You'll cause an error.
# </p>
# **STRING 20**
# WikiName of user under which periodic tasks are scheduled.
$Foswiki::cfg{Periodic}{UserName} = $Foswiki::cfg{AdminUserWikiName};
# **OCTAL EXPERT**
# File security (umask) for files written by periodic tasks.  Should generally prevent world access.
$Foswiki::cfg{Periodic}{Umask} = 007;
# **PATH**
# Log file for serious errors (what would go to the webserver error log if running under a webserver). %DATE% gets expanded
# to YYYYMM (year, month), allowing you to rotate logs.
$Foswiki::cfg{ErrorFileName} = '$Foswiki::cfg{DataDir}/error%DATE%.txt';
#---++ Built-in Periodic tasks
# Periodic tasks included in the base product.
#
# **SCHEDULE**
# Schedule for internal tasks (previously run by tick_twiki) such as expired sessions and edit locks.
# <br />
# Also the cleanup schedule used by simple plugins.
# <br />
# The default is to run at 01:15:14 every 3 days.
$Foswiki::cfg{CleanupSchedule} = '1 15 1-31/3 * * 14';
# **SCHEDULE EXPERT**
# Interval at which the daemon checks for configuration changes.  
$Foswiki::cfg{Periodic}{ReConfigSchedule} = '*/5 * * * * 17';
##
## KEEP THIS BLOCK LAST.
## 
## Search the directory containing this file for
## additional schedule declarations.  This allows
## other add-ons to put their schedules in this
## section rather than in their plugin's Config.spec
## -- if they have one.
##
# *SCHEDULES* 

1;
