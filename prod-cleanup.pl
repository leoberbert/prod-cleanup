#!/usr/bin/perl
#
#=============================================================
# Created: Tue 09 Jun 2020 11:57:22 AM -03
# Modified: Tue 31 Aug 2021 09:42:56 AM -03
#=============================================================

# This script does the following:
#
# * gzip all files older than <-z> days matching pattern <-p> and not matching pattern <-x>
# * delete all files older than <-d> days matching pattern <-p>.gz and not matching pattern <-x>
# * move all files older than <-m> days matching pattern <-p> and not matching pattern <-x> to directory <-t>

use File::Find;
use POSIX qw(strftime);
$HOME = './';

my $logname = "prod-cleanup ";
my $have_debug = 0;
$| = 1;

open LOG, ">", "/dev/null";

# print protocol type message
sub pmsg ($$;@) {
  my ($type, $msg) = (shift, shift);
  $msg = sprintf ($msg, @_) if (scalar @_);
  return if $type =~ m,^D,o && !$have_debug;
  # $have_error = 1 if $type =~ m,^[eEP],o;
  # $have_warn = 1 if $type =~ m,^W,o;
  my $date = strftime ("%d%m %H%M%S:", localtime);
  for my $m (split ("\n", $msg)) {
    printf "%s:%s%s:%s\n", $logname, $date, $type, $m if length $m;
    printf LOG "%s:%s%s:%s\n", $logname, $date, $type, $m if length $m;
  }
  # cleanup() if $type =~ m,^[PX],o;
  exit $1 if $type =~ m,^P([0-9]+),o;
  exit 1  if $type =~ m,^P,o;
  exit $1 if $type =~ m,^X([0-9]+),o;
  exit 0  if $type =~ m,^X,o;
  return 1;
}

sub mkdir_for ($) {
  my $path = shift;
  my @paths;
  while ($path =~ m,(.*)/+[^/]*$,o) {
    my $entry = $1;
    last if -d $entry;
    push @paths, $entry;
    $path = $entry;
  }
  while (scalar @paths) {
    mkdir (pop @paths) || return 0;
  }
  return 1;
}

{
  package Cleanup;
  
  sub Cleanup::new () {
    # @_ >= 1 && @_ <= 5 or croak 'usage: new Cleanup ()';
    my ($class, $od, $inst, $prefix, $mode) = @_;
    my %this = ( fake => 0, ziptime => undef, movetime => undef, deltime => undef );
    return bless \%this, $class;
  }
  
  sub Cleanup::set_fake ($$) {
    my ($this, $fake) = @_;
    $this->{'fake'} = $fake;
  }
  
  sub Cleanup::set_compress ($$) {
    my ($this, $compress) = @_;
    ::pmsg "P", "Compression delay ".$compress." is not numeric." unless $compress =~ m,^[0-9]*$,;
    $this->{'ziptime'} = $compress;
  }
  
  sub Cleanup::set_move ($$) {
    my ($this, $move) = @_;
    ::pmsg "P", "Moving delay ".$move." is not numeric." unless $move =~ m,^[0-9]*$,;
    $this->{'movetime'} = $move;
  }
  
  sub Cleanup::set_movedir ($$$$$) {
    my ($this, $daily, $movedir, $movetdir) = @_;
    ::pmsg "P", "Directory ".$movedir." does not exist" unless -d $movedir;
    $this->{'daily'} = $daily;
    $this->{'movedir'} = $movedir;
    $this->{'movetdir'} = $movetdir;
  }
  
  sub Cleanup::set_delete ($$) {
    my ($this, $del) = @_;
    ::pmsg "P", "Deletion delay ".$del." is not numeric." unless $del =~ m,^[0-9]*$,;
    $this->{'deltime'} = $del;
  }
  
  sub Cleanup::validate ($) {
    my $this = shift;
    ::pmsg "P", "Compression delay $this->{'ziptime'} is larger than deletion delay $this->{'deltime'}." if defined $this->{'ziptime'} && defined $this->{'deltime'} && $this->{'ziptime'} > $this->{'deltime'};
    ::pmsg "P", "Compression delay $this->{'ziptime'} is larger than move delay $this->{'movetime'}."    if defined $this->{'ziptime'} && defined $this->{'movetime'} && $this->{'ziptime'} > $this->{'movetime'};
    ::pmsg "P", "Move delay $this->{'movetime'} is larger than deletion delay $this->{'deltime'}."       if defined $this->{'movetime'} && defined $this->{'deltime'} && $this->{'movetime'} > $this->{'deltime'};
    ::pmsg "P", "Moving requested with -m, but not -t <MOVDIR> is given."                                if defined $this->{'movetime'} && !defined $this->{'movedir'};
  }
  
  sub Cleanup::compress ($$) {
    my ($this, $name) = @_;
    if ($this->{'fake'} & 2) {
      ::pmsg "I", "(Fake) Compressing " . $name;
    } else {
      ::pmsg "I", "Compressing " . $name . " ...";
      #if (system ("gzip", "--", $name)) {
      if (system ("xz", "--", $name)) {
        ::pmsg "E", "Failed to compress " . $name . " (" . $? . ").";
        return 0;
      }
    }
    return 1;
  }

  sub Cleanup::_date_from_file ($$) {
      my ($this, $name, $YYYYmm, $YYYYmmdd) = @_;
      if ($name =~ m,(?:.*/)?(?:.*_)?(?:[0-9][0-9][0-9][.])?(2[01][0-9][0-9][0-9][0-9])([0-9][0-9]),) {
        ($YYYYmmdd, $YYYYmm) = ($1."/".$2, $1);
      } else {
        my @mtime = localtime ((stat $ARGV[0])[9]);
        $YYYYmmdd = sprintf ("%04d%02d/%02d", $mtime[5]+1900, $mtime[4]+1, $mtime[3]);
        $YYYYmm   = sprintf ("%04d%02d", $mtime[5]+1900, $mtime[4]+1);
      }
      return $this->{'daily'} ? $YYYYmmdd : $YYYYmm;
  }

  sub Cleanup::move ($$$) {
    my ($this, $topdir, $name) = @_;
    $name =~ m,^((.*)/)?([^/]*)$,;
    my $file = $3;
    if (!defined $this->{'movetdir'}) {
      if ($this->{'fake'}) {
        ::pmsg "I", "(Fake) Moving " . $name . " to " . $this->{'movedir'};
      } else {
        ::pmsg "I", "Moving " . $name . " to " . $this->{'movedir'} . "...";
        if (link ($name, $this->{'movedir'}."/".$file)) {
          if (!unlink ($name)) {
            ::pmsg "E", "Failed to remove linked old file " . $name . " (" . $! . ").";
          }
        } else {
          if (system ("mv", "-f", $name, $this->{'movedir'}."/.")) {
            ::pmsg "E", "Failed to move " . $name . " to " . $this->{'movedir'} . " (" . $? . "," . $! . ").";
          }
        }
      }
    } else {
      my $YYYYmm = $this->_date_from_file ($name);
      my $relfile = $name;
      $relfile = substr ($relfile, length ($topdir) + 1) if substr ($relfile, 0, length ($topdir) + 1) eq $topdir . "/";
      my $targetfile = $this->{'movedir'} . "/" . $YYYYmm . "/" . $relfile;
      if (!::mkdir_for ($targetfile)) {
        ::pmsg "E", "Cannot create directories for " . $targetfile . " (" . $! . ").";
      }
      elsif ($this->{'fake'}) {
        ::pmsg "I", "(Fake) Moving " . $name . " to " . $targetfile . " using " . $this->{'movetdir'};
      } else {
        ::pmsg "I", "Moving " . $name . " to " . $targetfile . " using " . $this->{'movetdir'} . "...";
        if (link ($name, $targetfile)) {
          if (!unlink ($name)) {
            ::pmsg "E", "Failed to remove linked old file " . $name . " (" . $! . ").";
          }
        } else {
          if (system ("mv", "-f", $name, $this->{'movetdir'}."/$file.$$")) {
            ::pmsg "E", "Failed to move " . $name .  " to " . $this->{'movetdir'} . " (" . $? . "," . $! . ").";
          }
          elsif (link ($this->{'movetdir'}."/$file.$$", $targetfile)) {
            if (!unlink ($this->{'movetdir'}."/$file.$$")) {
              ::pmsg "E", "Failed to remove linked temp file " . $this->{'movetdir'}."/$file.$$" . " (" . $! . ").";
            }
          } else {
            ::pmsg "E", "Failed to atomically move " . $name . " to " . $targetfile . " (" . $! . ").";
          }
        }
      }
    }
  }

  sub Cleanup::delete ($$) {
    my ($this, $name) = @_;
    if ($this->{'fake'}) {
      ::pmsg "I", "(Fake) Deleting " . $name;
    } else {
      ::pmsg "I", "Deleting " . $name . " ...";
      if (!unlink ($name)) {
        ::pmsg "E", "Failed to delete " . $name . " (" . $! . ").";
      }
    }
  }
  
  {
    local our ($cleanup, $re, $exre, $topdir);
    
    sub Cleanup::_cb_compress () {
      my $this = $cleanup;
      return unless (-f _ && int (-M _) > ($this->{'ziptime'} - 1) && /$re/ && !/$exre/ && !/[.][gx]z$/);
      return unless $this->compress ($_);
      return unless (defined $this->{'movetime'} && int (-M _) > ($this->{'movetime'} - 1));
      $this->move ($topdir, $_ . ".gz");
    }

    sub Cleanup::_cb_move () {
      my $this = $cleanup;
      return unless (-f _ && int (-M _) > ($this->{'movetime'} - 1) && /$re/ && !/$exre/ && !(/[.][gx]z$/ && -f substr ($_, 0, -3)));
      $this->move ($topdir, $_);
    }

    sub Cleanup::_cb_delete () {
      my $this = $cleanup;
      return unless (-f _ && int (-M _) > ($this->{'deltime'} - 1) && /$re/ && !/$exre/);
      $this->delete ($_);
    }

    # do the actual work
    sub Cleanup::cleanup ($$$$) {
      my ($this, $patref, $expatref, $dirref) = @_;
      $cleanup = $this;
      my $texre = join ("|", map { my $p = $_; $p =~ s,[.],[.],go; $p =~ s,\[\[\.],[.,go; $p =~ s,[\\()|],\\$0,go; $p =~ s,[*],.*,go; $p } @$expatref);
      $exre = qr "^($texre)$";
      my $tre   = join ("|", map { my $p = $_; $p =~ s,[.],[.],go; $p =~ s,\[\[\.],[.,go; $p =~ s,[\\()|],\\$0,go; $p =~ s,[*],.*,go; $p }   @$patref);
      $re = qr "^($tre)$";
      if (defined $this->{'ziptime'}) {
        for $topdir (@$dirref) {
          File::Find::finddepth ( { wanted => \&Cleanup::_cb_compress, no_chdir => 1, follow_fast => 1, follow_skip => 2  }, ($topdir,));
        }
        $re = qr "^($tre)[.][gx]z$";
      }
      if (defined $this->{'movetime'}) {
        for $topdir (@$dirref) {
          File::Find::finddepth ( { wanted => \&Cleanup::_cb_move, no_chdir => 1, follow_fast => 1, follow_skip => 2  }, ($topdir,));
        }
      }
      if (defined $this->{'deltime'}) {
        File::Find::finddepth ( { wanted => \&Cleanup::_cb_delete, no_chdir => 1, follow_fast => 1, follow_skip => 2  } , @$dirref);
      }
    }
  }
}


sub usage() # Print a usage statement and die.
{
    pmsg "E", "Usage: prod-cleanup [-n|-N] [-z <zdays>] [-m mdays (-t <path>|-a <archivetype>)] [-d <days>] [-p <pattern>]... [-x <exclude>] dir1...";
    pmsg "I", "   -n              fake - do not execute any gzip, rm or move";
    pmsg "I", "   -N              fake deletion - do not execute any rm or move";
    pmsg "I", "   -z <zdays>      days before compressing (default: no compression)";
    pmsg "I", "   -d <days>       days before deletion (default: 42)";
    pmsg "I", "   -p <pattern>    shell pattern to match files against (default: *.old)";
    pmsg "I", "   -x <exclude>    shell pattern of files to exclude (default: none)";
    pmsg "I", "   dirN            Nth directory to scan in";
    pmsg "P", "Check arguments.";
}

usage() unless exists $ARGV[0];
usage() if $ARGV[0] eq "--help" || $ARGV[0] eq "-h" || $ARGV[0] eq "-H";
pmsg "1", "Cleaning up @ARGV";
pmsg "P", "Environment variable HOME is not set!" unless length ($HOME);
pmsg "P", "HOME does not exist" unless -d $HOME;
if (! -d $HOME . "/log/.") {
  pmsg "W", "HOME/log does not exist - create it!";
  mkdir $HOME . "/log";
  pmsg "P", "Could not create ".$HOME."/log" unless -d $HOME . "/log/.";
}

my $logfile = $HOME . "/log/cleanup.log." . strftime ("%Y%m", localtime);
open LOG, ">>", $logfile || pmsg "P", "Cannot redirect for logging.";

my $cl = new Cleanup();
my @pats;
my @expats;

while (exists $ARGV[0] && $ARGV[0] =~ m,^-(.*)$,) {
  shift;
  my $opt = $1;
  if    ($opt eq "n") { $cl->set_fake (2); }
  elsif ($opt eq "N") { $cl->set_fake (1); }
  elsif ($opt eq "D") { $have_debug = 1; }
  elsif ($opt eq "-") { last; }
  elsif (!exists $ARGV[0] && $opt =~ m,^([zdmaAtpx]|DID)$,) { pmsg "P", "Option ".$opt." requires an argument."; }
  elsif ($opt eq "z") { $cl->set_compress (shift); }
  elsif ($opt eq "d") { $cl->set_delete (shift); }
  elsif ($opt eq "m") { $cl->set_move (shift); }
  elsif ($opt eq "a") { $cl->set_movedir (0, $HOME . "/archive/" . shift, $HOME . "/archive/incoming"); }
  elsif ($opt eq "A") { $cl->set_movedir (1, $HOME . "/archive/" . shift, $HOME . "/archive/incoming"); }
  elsif ($opt eq "t") { $cl->set_movedir (0, shift); }
  elsif ($opt eq "p") { push @pats, shift; }
  elsif ($opt eq "x") { push @expats, shift; }
  elsif ($opt eq "DID") { $logname = substr ((shift) . "            ", 0, 12); }
  else { pmsg "P", "Unknown option ".$opt; }
}
$cl->validate();
pmsg "P", "No directories to clean up!" unless scalar @ARGV;
@pats=("*.old") unless scalar @pats;
$cl->cleanup (\@pats, \@expats, \@ARGV);
pmsg "X", "Done";
