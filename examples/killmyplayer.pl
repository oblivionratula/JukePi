#!/usr/bin/perl -w
# Stripped down script which doesn't use the slow Last.FM library.
# Simple player to insert Last.FM "Scroble" flag into Calliope database while 
# playing MP3s from a playlist. Or singly?
###################
# Major overhaul of storing working playlist in db so it can be manipulated 
# while playing. Playing may be handled by another instance with a -c flag.

use strict;  ### Turn these back on if developing.
use warnings; #### ^^^^^^^^^^^^^^^^^^^^^^^
use DBI;
use Config::Simple;
use File::HomeDir qw(my_home);

STDOUT->autoflush;

my %opt = ( 'a' => '1' ); 
my $cfgfile = File::HomeDir->my_home . '/' . '.myplayer.cfg';
Config::Simple->import_from($cfgfile, \%opt);

$opt{dbhost}='127.0.0.1' unless defined $opt{dbhost};
$opt{dbport}=3306 unless defined $opt{dbport};
$opt{dbuser}='calliope' unless defined $opt{dbuser};
$opt{dbpass}='calliope' unless defined $opt{dbpass};
#Some settings left here:
$opt{dbpath_base}='/storage/main_music_repository';
$opt{killcode}=999999999;

#Data Source Name
my $dsn="DBI:mysql:database=$opt{database};host=$opt{dbhost};port=$opt{dbport}" ;
#DBHandle
my $dbh = my_connect($dsn, %opt);

if ($opt{a}) {
    print "Inserting stop flag into DB playlist." if $opt{v};
    $dbh->do("INSERT INTO listelement (listid, elementid, type, playorder, uzer) VALUES ( '$opt{listid}', '$opt{killcode}', 'song', '0', 'mmatula') ");
    die "As you wish!  The seed has been planted to kill the player after this song. \nNext time, hate the game.\n";
}
#Disconnect from DB
$dbh->disconnect();


################################

sub help {
    my ($message) = @_;
    print "\n$message\n\n";
    print "Plays a playlist of filenames, submits to Last.FM and accounts plays in Calliope db\n";
    print "Modes of operation:\n";
    print " -a = abort! - Not really , but I'm running out of letters. Inserts a stop-plag into DB playlist to die after the current song.\n";
    exit
}

sub my_connect {
    my ($dsn, %opt) = @_;
    my $dbh= DBI->connect($dsn,$opt{dbuser},$opt{dbpass}) 
        || die "Could not connect to database: $DBI::errstr";
    return $dbh;
}
