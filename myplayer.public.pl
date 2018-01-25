#!/usr/bin/perl -w
# Simple (HA!) player to insert Lat.FM "Scroble" flag into Calliope database while 
# playing MP3s from a playlist. Or singly?
###################
# Major overhaul of storing working playlist in db so it can be manipulated 
# while playing. Playing may be handled by another instance with a -c flag.
### NOTE! To randomize existing DB playlist in place, you can do something like:
# UPDATE`listelement` SET playorder = (RAND() * 500) WHERE listid = 12

###Make use of song flag #5 'Do Not Play' for avoiding crap songs.



### To Do:
# Enable 'slave mode' to not remove/scrobble plays if another player is running on another machine?

#use Benchmark;
use strict;
use warnings;
use DBI;
use Date::Parse;
use Scalar::Util qw(looks_like_number);
use vars qw( %opt );
use List::Util qw(shuffle);
use Getopt::Std;
use Try::Tiny;
use Net::LastFM;    ##### This module is VERY slow to load on pi
#use Data::Dumper;
use Config::Simple;
use File::HomeDir qw(my_home);
use IO::Prompter;

STDOUT->autoflush;

my $opt_string = 'acdehjklmprsvxf:o:';   # m = missing-OK - keeps playing if song missing from HD.
my $cfgfile = File::HomeDir->my_home . '/' . '.myplayer.cfg';

#Validate options:
# Load settings file into %opt HASH
#my  $cfg =   Don't think this is needed remove later.
Config::Simple->import_from($cfgfile, \%opt);
$opt{cfgfile}=$cfgfile;

# Now load command line options:
# This will overwtire anything from the settings file.
getopts( "$opt_string", \%opt);
help("Help . . .") if ($opt{h}) ;

#Verify or set some sane defaults on things
die "Player not selected in config file.\n" unless defined($opt{'player'});
die "Player: $opt{'player'} does not seem to exist.  Check settings.\n" unless (-e $opt{'player'});
check_filepath(%opt) if ($opt{path_mod} && $opt{c});

$opt{dbhost}='127.0.0.1' unless defined $opt{dbhost};
$opt{dbport}=3306 unless defined $opt{dbport};
$opt{dbuser}='calliope' unless defined $opt{dbuser};
$opt{dbpass}='calliope' unless defined $opt{dbpass};
#Some settings left here:
$opt{dbpath_base}='/storage/main_music_repository';
$opt{killcode}=999999999;
$opt{last_api_key} = 'getyourown'; 
$opt{last_api_secret} = 'getyourown';

# Figure out what mode we're in:
my $ops_mode = 0;
++$ops_mode if ($opt{a});  # Abort playing after current song
++$ops_mode if ($opt{o});  # Plays one song from filename
++$ops_mode if ($opt{c});  # "Calliope" mode - plays from DB.
++$ops_mode if ($opt{e});  # EDIT PLaylist.  Placeholder for now.  
++$ops_mode if ($opt{f});  # Load a playlist from a file - by filname, I think.
++$ops_mode if ($opt{'s'});  # Search mode. Add songs to playlist or play them immediately. 
++$ops_mode if ($opt{l});  # Loads an existing Calliope playlist.
++$ops_mode if ($opt{j});  # Jukebox mode - Just play a song at a time at random.
++$ops_mode if ($opt{x});  # Show play history.
--$ops_mode if ($opt{c} && $opt{j}); # Allows jukeboxing after the playlist empties.  I think.  Need to test. 

#help("You need to specify at least one mode (-a, -c, -o, -f, or -s)!") if ($ops_mode < 1);
if ($ops_mode < 1) {
    print "No operation mode specified.\nDefaulting to 'Calliope' Mode (playing DB playlist).\n\n";
    $opt{c}=1;
    sleep 1;
}
help("You can ONLY specify ONE mode (-a, -c, -o, -f, -j, -l, or -s)!") if ($ops_mode > 1); 
if ($opt{j} && $opt{k}) {
    print "-k is redundeant and ignored if -j is used!\n" ;
    sleep 2;
}

my @playlist;
#Data Source Name
my $dsn="DBI:mysql:database=$opt{database};host=$opt{dbhost};port=$opt{dbport}" ;
#DBHandle
my $dbh = my_connect($dsn, %opt);

#my $artists = join(', ', get_artist_info ($dbh, 23680));    # artists.artist
#die $artists;

if ($opt{e}) {  #  edit playlist.
    my $quit=0;
    my $offset=0;
    my $perpage=15;
    my $sth_count=$dbh->prepare("SELECT COUNT(elementid) FROM listelement WHERE listid = ?;");
    my $change=1;
    my %song_batch;
    until ($quit) {
        $sth_count->execute($opt{listid});
        my ($count) = $dbh->selectrow_array($sth_count);
        if ($change) {
            print "=======================================================================\n";
            %song_batch = display_db_playlist($dbh, $perpage,$offset, "Of $count songs in queue, showing:", %opt);
        }
        $change = 0;
        print "=======================================================================\n";
	my $action = prompt("1) Page Up 2) Page Down 3) Delete Song 4) Move Song 5) Reshuffle 9) Quit: ", -integer, -single, -def=>2);
	if ($action <= 2) {
            if ($action == 1 )  {
                if ($offset > 0) { ++$change } else { print "\nAlready at top of list!\n"; }
                $offset -= $perpage;
            }
            if ($action == 2) {
                if ($offset+$perpage < $count) { ++$change } else { print "\nAlready at end of list!\n"; }
                $offset += $perpage;
            }
            if ($offset <= 0) {
                $offset = 0;
            } elsif ($offset+$perpage > $count) {
                $offset = $count - $perpage;
            } #else { ++$change }
            next;
       } elsif ($action == 3) {
           my $deletekey = prompt ("Enter song ID (not playorder): ", -integer);
           if (defined($song_batch{$deletekey})) {
               if (prompt("Really delete $song_batch{$deletekey}{'song'}?", -syn)) {
                       print "Ok, removing $song_batch{$deletekey}{'song'} from playlist.\n";
                       $dbh->do("DELETE FROM listelement WHERE le_key = $song_batch{$deletekey}{'key'};") || warn "something went wrong.";
                       ++$change;
               } else {
                   print "You were only joking?  Ok.\nWhat now?";
               }
           } else {
               print "That doesn't look like a valid Song ID  (on this screen). Try again.\n";
           }
       } elsif ($action == 4) {
           my $movekey = prompt ("Enter song ID to move: ", -integer);
           if (defined($song_batch{$movekey})) {
                print "Moving " . $song_batch{$movekey}{'song'} . ' by ' . $song_batch{$movekey}{'artists'} . "\n";
                my $new_order = prompt ("Enter new play placement. May not act correctly if a song is already in that spot. Yet. ", -integer);
                $dbh->do("UPDATE listelement SET playorder = $new_order WHERE le_key = $song_batch{$movekey}{'key'};");
                print "Ok, moved  $song_batch{$movekey}{'song'} to position # $new_order.\n";
                ++$change;
           } else {
               print "That doesn't look like a valid Song ID  (on this screen). Try again.\n";
           }
       } elsif ($action == 5) {
           if (prompt ("Are you sure you want to shuffle the playlist?", -syn)) {
               playlist_to_db(14);
               print "\n\nOk, reshuffled.\n";
               ++$change;
           } else { print "Ok, leaving playlist as is.\n"; }
       } else { ++$quit; } # if $action == 9;
    }
    $dbh->disconnect();
    exit;
}

if ($opt{x}) { #show recently played tracks (up to last 100?).
    my $quit=0;
    my $how_much_history = prompt("How far back should I load? [100 tracks]", -integer, -def=>100);
    my $perpage = prompt("How many lines per page? [15]", -integer, -def=>15);
    my %songs;
    my @cols = qw(songid song file length album tracknum played picked pwhen cancelled);
    my $col_list = join(', ', @cols);
    my $query = "SELECT $col_list FROM `songs` WHERE 1 ORDER BY pwhen DESC LIMIT ?;";
    my $sth = $dbh->prepare($query);
    until ($quit) {
        my $offset=0;
        $sth->execute($how_much_history) or die "Cannot execute: " . $sth->errstr();
        my $itemnumber=1;
#        print "Loading history . . . \n";
        while (my @row = $sth->fetchrow_array) {
            my $j = 0;
#            print "$itemnumber songs loaded.\n" if !($itemnumber % 10);
            foreach my $key(@cols) {
                    $songs{$itemnumber}{$key} = $row[$j++];
            }
            $songs{$itemnumber}{'artists'} = join(', ', get_artist_info($dbh, $songs{$itemnumber}{'songid'}));
            $itemnumber++;
        }
        my $reload = 0;
        my $skip = 0;
        $~ = "PLAYED";
        until ($reload || $quit) {
            unless( $skip) {
                for (my $i=$offset+1; $i <= $perpage+$offset; $i++) {
                    write(STDOUT);

format PLAYED =
@### @<<<<<<<<<<<<<<<<<... @<<<<<<<<<<<<<<<<<<<<<... @<<<<<<<<<<<<<<<<<<<<<...
$i, $songs{$i}{artists}, $songs{$i}{song}, $songs{$i}{album} 
.
                }
            }
            $skip = 0;
            print "=======================================================================\n";
            my $action = prompt("1) Page Up 2) Page Down 3) More Song Info 4) Queue Song Again 5) Refresh list 9) Quit: ", -integer, -single, -def=>2);

            if ($action <= 2) {
                if ($action == 1 )  {
                    if (!($offset > 0)) { print "\nAlready at top of list!\n"; $skip++; }
                    $offset -= $perpage;
                }
                if ($action == 2) {
                    if (!($offset+$perpage < $how_much_history)) { print "\nAlready at end of list!\n"; $skip++; }
                    $offset += $perpage;
                }
                if ($offset <= 0) {
                    $offset = 0;
                } elsif ($offset+$perpage > $how_much_history) {
                    $offset = $how_much_history - $perpage;
                }
                next;
            } elsif ($action == 3) {
                my $id = prompt("Which song?", -integer);
                
                foreach my $key(@cols) {
                    print $songs{$id}{$key} . ' ';
                }
                print "\n";
                $skip++;
            } elsif ($action == 4) {
               my $playagain = prompt ("Enter song ID to queue again: ", -integer);
               warn "I still need to figure this out.";
               $skip++;
               # $dbh->do("UPDATE listelement SET playorder = $new_order WHERE listid = $opt{listid} AND elementid = $movekey;");
                    # print "Ok, moved  $song_batch{$movekey}{'song'} to position # $new_order.\n";
                    # ++$change;
               # } else {
                   # print "That doesn't look like a valid Song ID  (on this screen). Try again.\n";
               # }
            } elsif ($action == 5) {
                $reload++;
                
            } else { ++$quit; } # if $action == 9;
        }
    }
    $dbh->disconnect();
    exit;
}


#Find the Flag # for 'Scrobble'
my $sth = $dbh->prepare('SELECT flagid FROM flags WHERE flag LIKE "Scrobble"');
my @row = $dbh->selectrow_array($sth); 
unless (@row) { die "No result returned."}
$opt{scrobflag} = $row[0] || die "You need to set up a Flag in Calliope called 'Scrobble.'";
$sth->finish();
print "Scrobble flag is: $opt{scrobflag}\n" if $opt{d};

#Find the Flag # for 'Do Not Play'
$sth = $dbh->prepare('SELECT flagid FROM flags WHERE flag LIKE "Do Not Play"');
@row = $dbh->selectrow_array($sth); 
unless (@row) { die "No result returned."}
$opt{dnpflag} = $row[0] || die "You need to set up a Flag in Calliope called 'Do Not Play.'";
$sth->finish();
print "Do Not Play flag is: $opt{dnpflag}\n" if $opt{d};


if ($opt{a}) {
    print "Inserting stop flag into DB playlist." if $opt{v};
    $dbh->do("INSERT INTO listelement (listid, elementid, type, playorder, uzer) VALUES ( '$opt{listid}', '$opt{killcode}', 'song', '0', 'mmatula') ");
    print "As you wish!  The seed has been planted to kill the player after this song. \nNext time, hate the game.\n";
    $dbh->disconnect();
    exit;
}
my $elements=$dbh->prepare('SELECT COUNT(le_key) FROM listelement WHERE listid = ?');
if ($opt{c}) {    # "Calliope" mode - play from DB playlist #12
    $dbh->do("DELETE FROM listelement WHERE elementid = '$opt{killcode}'");   # If we're just starting, blast out any killcodes.
    $opt{sleeper}=0;
    $opt{sleep_interval}=5;
    my $remove_element=$dbh->prepare('DELETE FROM listelement WHERE le_key = ? LIMIT 1');
    my $song=$dbh->prepare('SELECT le_key, elementid FROM listelement WHERE listid = ? ORDER BY playorder LIMIT ?,1');
    my $queenkiller=$dbh->prepare('SELECT le_key, elementid FROM listelement WHERE listid = ? AND elementid = ? LIMIT 1');
    my $next_song=$dbh->prepare('SELECT elementid FROM listelement WHERE listid = ? ORDER BY playorder LIMIT ?,?');
    srand();
    init_lastfm(\%opt);
    while ($opt{c}) {  # "calliope mode" for lack of a better term. Play latest song from $opt{listid} until stopped or there are no more.
        $opt{juked}=0;
        my ($key, $songid) = $dbh->selectrow_array($queenkiller,undef,($opt{listid}, $opt{killcode}));
        if ($songid) {  #nuking all killcodes, in case more than one was entered.
            $dbh->do("DELETE FROM listelement WHERE elementid = '$opt{killcode}'");
            die "I killed it 'cause you needed revenge.\n(Or just a break.)\n"
        }
        my $offset=0;
        #If Randomizing, get row count and set a random row for the fetch.
        my ($songs_in_queue) = $dbh->selectrow_array($elements,undef,($opt{listid}));
        if ($opt{r}) {
            $offset = int(rand($songs_in_queue));
            print "Offset: $offset\n" if $opt{v}; 
        } #Else, use preset offset of 0.
        ($key, $songid) = $dbh->selectrow_array($song,undef,($opt{listid}, $offset)); 
        unless ($songs_in_queue <= 1 || $opt{r}) {
            my $limit=5;
            $next_song->execute($opt{listid}, $offset+1, $limit);
            my @upcoming;
            while (my @row = $next_song->fetchrow_array) {
                push @upcoming, $row[0];
            }
            print "Next " . @upcoming . " songs:\n($songs_in_queue songs in queue.)\n=======================\n";
            display_playlist_by_songid($dbh, @upcoming);
        }
        unless ($songid) { 
            if ($opt{j}) {
                print "Playlist is empty - picking something you haven't heard in a while/before.\nAdd more songs with -s\n";
                my @results = pick_one($dbh,undef,3,undef,$opt{dnpflag});  # Change playmode (currently 3) to 2 to ONLY pick unplayed songs.
                $songid = $results[0][1];
                $opt{juked}=1;
            } elsif ($opt{k}) {
                if ($opt{sleeper} == 0) {
                    print "Nothing left to play. Add some songs to the queue or I'll DIE!\n" ;
                    $opt{coma}=0;
                }
                sleep $opt{sleep_interval};
                if ($opt{sleeper} >= 60) {
                    print "Going into a coma." if ($opt{coma} == 0);
                    $opt{sleep_interval} = 120;  # Why was this 20 MINUTES (1200) It's insane.
                    $opt{coma}++;
                    print "Coma: $opt{coma}\n";
                }
                die "I can't wait around forever!\n" if ($opt{coma} == 10); #Upping from 6 to 10 since coma interval was reduced.
                $opt{sleeper}++;
                print "Sleeper is $opt{sleeper}\n";
                next;
            } else {
                die "I've run out of things to play. I will stay alive longer with the -k option.\n"
            }
        }
        print "Would play song # $songid now.\n" if $opt{d};
        my ($songok,$filename)=checksong($songid, $dbh, %opt);
        die "Dying on missing songID: $songid\n$filename\nWil also end up here if I run out of unplayed songs to 'jukebox.'\n" unless $songok;
        #On safe return, remove song from DB list.
        print "Juked: $opt{juked}\n" if $opt{d};
        $remove_element->execute($key) unless $opt{juked};
        if ($songok==1) {
            print "Ok, removing songID: $songid\n$filename\nfrom playlist, but skipping.\n";
        } else {
            playsong ($songid, $dbh, %opt);
        }
        $opt{sleeper}=0; # Reset sleep counter after a song is played.
    }
}

# If building playlists, going to set this to loop until exited.
my $loop_playlists = 1;
while ($loop_playlists) {
    # Read in playlist if -f specified
    #	(Randomize if -r)
    if ($opt{f}) {
        my $file = $opt{f};
        open (FH, "< $file") or die "Can't open $file for read: $!";
        #@playlist[0] = 
        while (<FH>) {
            my $filename = $_;
            chomp $filename;
            my $id = file_to_songid($dbh,$filename,%opt);
            if ($id) {
                push @playlist, [ $filename, $id ];
            } else {
                print "Song $filename not found in database. Perhaps you need to load it with Calliope?\n";
            }
        }
        print Dumper @playlist if $opt{d};
        close FH or die "Cannot close $file: $!";
    }
    if ($opt{o}) {
        my $id = file_to_songid($dbh,$opt{o},%opt);
        if ($id) { 
            @playlist = [($opt{o}), $id];
            print "Parsed as: " . Dumper(\@playlist) if ($opt{d});
            print "-r (randomize) does nothing in One Song mode.\n" if ($opt{r});
        } else {
            die "Song not found in database. Try again.\n"
        }
    }

    if ($opt{j}) {
            $opt{juked}=1;
            if ($loop_playlists==1) {
                $opt{juke_dnp} = numeric_user_input("1) Respect or or 2) Ignore 'Do Not Play' flag?\n",1,2);
                $opt{juke_mode} = numeric_user_input("1) Play any track? 2) Play only unplayed tracks? 3) Play something not heard in over 6 months?\n",1,3);
                $opt{juke_limit} = numeric_user_input("Limit song length?\n1) Only < 10 minutes 2) Only < 20 minutes\n3) Only < 1 hour 4) Unlimited\n",1,4);
            }
            print "Jesus is taking the wheel . . . \n";
            @playlist = pick_one($dbh,$opt{juke_dnp},$opt{juke_mode},$opt{juke_limit},$opt{dnpflag});
            #IAMHERE
            die "The jukebox came up empty. Figure out why.\n" unless $playlist[0][1];
    }
        

    if ($opt{s}) {
        @playlist = search_db($dbh);
        print "Got a playlist from the database.\n" if ($opt{v});
    }

    if ($opt{l}) {
        @playlist = calliope_lists($dbh);
    }

    #	(Randomize if -r)
    if ($opt{r}) {
        print "Shuffling playlist:\n" . Dumper(\@playlist) if ($opt{v} || $opt{d});
        print "Randomizing.\n";
        @playlist = shuffle(@playlist);
        print "Shuffled as: " . Dumper(\@playlist) if ($opt{d});
        # Too slow for large lists!!!    
        # Because it searches agains the filename, not songid!!!!!  Fixed with = instead of LIKE
        display_playlist($dbh, @playlist);
    }

    #Where to put new songs?
    display_playlist($dbh,@playlist) unless ($opt{s} || $opt{r} || $opt{l}) || $opt{j}; # Already done.
    my $playorsave;
    if ($opt{j}) {
        $playorsave=2;
    } else {
        $playorsave = numeric_user_input("1) Queue in database (default) or 2) Play now?\n",1,2);
    }
    if ($playorsave == 1 ) {
        my $playlistmode;
        my ($playlist_count) = $dbh->selectrow_array($elements,undef,($opt{listid}));
        if ($playlist_count) {
            $playlistmode= numeric_user_input("1) Prepend  2) Append 3) Replace current queue or 4) Shuffle everything together?\n",1,4);
        } else {
            $playlistmode=3;
        }
        #### Push playlist to DB
        playlist_to_db($playlistmode,@playlist);
        print "Done! Run with -c to play database playlist.\nAlso use -r if you want to randomize playback.\n";
        
    } else {
        # Loop through playlist
        check_filepath(\%opt);
        init_lastfm(\%opt);
        for my $i (0 .. $#playlist) {
            my $songid=$playlist[$i][0];
            print "\n\nGoing to play $songid\n" if $opt{d};
            my ($songok,$filename)=checksong($songid, $dbh, %opt);
            die "Dying on missing songID: $songid\n$filename\n" unless $songok;
            #On safe return, remove song from DB list.
            if ($songok==1) {
                print "Ok, removing songID: $songid\n$filename\nfrom playlist, but skipping.\n";
            } else {
                playsong ($songid, $dbh, %opt);
            }
        }
        print "End of playlist. Done.\n" unless $opt{j};
    }
    $loop_playlists++;
    #### Put end query here.
    my $keep_looping;
    if ($opt{j}) {
        $keep_looping=1;
        print "I just keep playing until you stop me. Need to figure out an iterrupt.\nFor now, use ^c\n";
    } else {
        $keep_looping=numeric_user_input("1) Select more or 2) quit?\n",1,2);
    }
    undef $loop_playlists unless ($keep_looping ==1);
#IWASHERE
#    if ( $keep_looping and !$dbh->ping ) {  ### attempt to catch closed connections
#        $dbh = my_connect($dsn, %opt);  #		This didn't work. It silently ate a big existing playlist probably due to a stale handle.
#        my $goomba=1;
#        until ($keep_looping == 2) {
#            warn $dbh->ping;
#            
#            sleep 5;
#            $dbh = my_connect($dsn, %opt);
#        }
#    }
}
#Disconnect from DB
$dbh->disconnect();


################################
sub playsong {
    my ($song, $dbh, %opt) = @_;
    my $query = "SELECT songid, song, file, length, mbid, album, tracknum, played, picked, pwhen, cancelled FROM `songs` WHERE ";
    print "Playing: $song\n" if ($opt{v});
    # Read song info from db
    if (looks_like_number($song)) {
        #we have song ID, need filename
        $query .= " `songid` = ? LIMIT 1";
    } else {
        #We have the filename, need songID
        $query .= " `file` = ? LIMIT 1";
    }
    print "Query: $query\n" if ($opt{d});
    my $sth = $dbh->prepare($query);
    $sth->execute($song) or die "Cannot execute: " . $sth->errstr();
    $sth->bind_columns(\my($songid, $songtitle, $filename, $song_length, $mbid, $album, $tracknum, $times_played, $times_picked, $last_play, $times_cancelled ));
    die("Song returned too few or many results!  Dying.\n$filename\n") if ($sth->rows != 1);
    while (my @row = $sth->fetchrow_array) {
        print "Row: " . Dumper(\@row) if ($opt{d});
        #get start time
        my $stime = time();
        $filename = fixname($filename,%opt);
        # Play song
        my $artists = join(', ', get_artist_info ($dbh, $songid));    # artists.artist
        my $command = $opt{player} . " ".$opt{player_opts} . ' "' . $filename . '"';
        if ($opt{v}) {
            print "Play with: $command\n" ;
        }
        my (undef, $scrobbles)=find_scrobbles($songid, $dbh, $mbid, %opt);
        my $duration=parse_seconds($song_length);
        print "Calling $opt{'player'} . . ." if $opt{v};
        $times_played=0 unless $times_played;
        $times_cancelled=0 unless $times_cancelled;
        $times_picked=0 unless $times_picked;
        $scrobbles= 0 unless $scrobbles;
        $last_play = 'Never' unless $last_play;
        my $playing = "Playing \"$songtitle\" by $artists";
        my $hilight='         ';
#        my $lolight='';
        for (my $i=0; $i < length($songtitle); $i++) {
#                $lolight .= '-';
                $hilight .= '^';
        }
#        print "\n$lolight";
        print "\n$playing\n$hilight\nTrack $tracknum on $album\n$duration - (SongID: $songid)\tLast played: $last_play\n" .
                "Plays: $times_played\tPicked: $times_picked\tSkipped: $times_cancelled\tScrobbled: $scrobbles\n"; 
        undef $duration;
        undef $artists;
        undef $scrobbles;
        system($command);
        print '#######################'."\n";
        my $ptime = (time() - $stime);
        # if play time was >1/2 track length 
        if ($ptime > ($song_length/2)) {
            print "Played for $ptime seconds. Scrobbling: $songid\n" if ($opt{v});
            #UPDATE songs.pwhen and INC songs.played and songs.picked
            my $picked = '';
            $picked = ", `picked` = `picked` + 1" unless $opt{juked} ;  # Don't inc 'picked' if played in jukebox mode.
            my $update_query = "UPDATE `songs` SET `played` = `played` + 1, `pwhen` = now() $picked WHERE `songid` = '$songid'";
            print "Update Query: \n$update_query\n" if ($opt{d});
            my $sth = $dbh->prepare($update_query);
            $sth->execute() or die "Cannot execute: " . $sth->errstr();
            $sth->finish();
            #insert Scrobble flag in db
            my $insert_query = "INSERT INTO `songflag` (`songid`, `flagid`, `uzerid`) VALUES  ('$songid', '$opt{scrobflag}', '$opt{uzerid}')";
            print "INSERT Query: \n$insert_query\n" if ($opt{d});
            $sth = $dbh->prepare($insert_query);
            $sth->execute() or die "Cannot execute: " . $sth->errstr();
            $sth->finish();
        } else {
            print "Didn't play long enough to scrobble. Play time = $ptime needed half of $song_length.\n";
            #UPDATE pwhen and INC songs.cancelled
            my $update_query;
            if ($opt{juked}) { #Won't ding for skipping a jukebox tune.
                $update_query= "UPDATE `songs` SET `pwhen` = now() WHERE `songid` = '$songid'";
            } else {
                $update_query= "UPDATE `songs` SET `cancelled` = `cancelled` + 1, `pwhen` = now() WHERE `songid` = '$songid'";
            }
            print "Update Query: \n$update_query\n" if ($opt{d});
            my $sth = $dbh->prepare($update_query);
            $sth->execute() or die "Cannot execute: " . $sth->errstr();
            $sth->finish();
        }
        
    }
}

sub checksong {
    my ($song, $dbh, %opt) = @_;
    my $mybreak++;
    my $query;
    print "Checking: $song\n" if ($opt{v});
    # Read song info from db
    my $filename;
    if (looks_like_number($song)) {
        #we have song ID, need filename
        $query = "SELECT file FROM `songs` WHERE `songid` = ?";
        print "Query: $query\n" if ($opt{d});
        my $sth = $dbh->prepare($query);
        $sth->execute($song) or die "Cannot execute: " . $sth->errstr();
        $sth->bind_columns(\my($found_filename));
        die("Song returned too few or many results!  Dying.\n$found_filename\n") if ($sth->rows != 1);
        while (my @row = $sth->fetchrow_array) {
            print "Row: " . Dumper(\@row) if ($opt{d});
        }
        $filename = $found_filename;
    } else {
        $filename=$song;
    }        
    $filename = fixname($filename,%opt);
    # Check if filename is valid
    my $proceed=2;
    print "Filename: $filename\tExists? ". (-e $filename) . "\tNot exists\t" . (!-e $filename) ."\n" if $opt{d}; 
    if (!-e $filename) {
        print "\n\nFile: $filename does not exist.\nIs music repo mounted?\n\n";
        if ($opt{m} || $opt{j}) {
            $proceed=1;
        } else { 
            if (prompt "Would you like me to skip this song? If not, I'll die.(y/n)", -syn) {
                $proceed=1;
            } else {
                $proceed=0;
            }
        }
    }
    return ($proceed,$filename); # 0 = not found, die. 1 = not found, but let's continue. 2 = All good.
}

sub fixname {
    my ($filename, %opt) = @_;
    if (defined($opt{path_mod})) {
        $filename =~ s/$opt{dbpath_base}/$opt{path_mod}/;
    }
    return($filename);
}

sub search_db {
    my ($dbh) = @_;
    my @playlist;
    #loop until we get a playlist we're happy with.
    until (@playlist) {
        print "Search for (case-insensitive, leave blank for any)\n";
        print "Artist? ";
        my $artist = <STDIN>;
        chomp($artist);
        $artist = "%$artist%";
        print "Search for compilations instead of just songs? (Y/N) ";
        my $comp = <STDIN>;
        chomp($comp);
        print "Album? ";
        my $album = <STDIN>;
        chomp($album);
        $album = "%$album%";
        print "Song? ";
        my $song = <STDIN>;
        chomp($song);
        $song = "%$song%";
#        my $no_chirp = prompt "Exclude Chirp Radio recordings? (y/n)", -syn, -dy;
#        if ($no_chirp) {
#            $no_chirp = " AND songs.album NOT LIKE 'Chirp Radio' ";
#        } else {
#            $no_chirp = '';
#        }
        my $not_long = prompt "Exclude tracks over 20 minutes? (y/n)", -syn, -dy;
        if ($not_long) {
            $not_long = " AND songs.length < 1200 ";
        } else {
            $not_long = '';
        }
        my $extra = '';
        my $preface = '';
        my $appendage = '';
        my $sort = numeric_user_input("1)Random (default) 2)Recently Played 3)Least Recent 4)Most Picked 5)Least Picked\n6)Album Order 7)Most Recently Added 8)Least Recently Added 9)Most Scrobbled\n10)Unplayed (newest to oldest) 11) Unplayed (oldest to newest)\n12)Unplayed (album order (can get weird if multiple albums))\n",1,12);
        # 10, 11, $extra, $preface and $appendage added 3/24/2016
 
              ####  Had a note to add: 10) A chunk of x songs from the y most scrobbled. (To Do)\n",1,10);
        if ($sort == 2) {
            $sort = "songs.pwhen DESC";
        } elsif ($sort == 3) {
            $sort = "songs.pwhen";
        } elsif ($sort == 4) {
            $sort = "songs.picked DESC";
        } elsif ($sort == 5) {
            $sort = "songs.picked";
        } elsif ($sort == 6) {
            $sort = "songs.album, songs.tracknum";
        } elsif ($sort == 7) {
            $sort = "songs.lwhen DESC";
        } elsif ($sort == 8) {
            $sort = "songs.lwhen ASC";
        } elsif ($sort == 9) {
            $sort = "songs.lastFMscrobbles DESC";
        } elsif ($sort == 10) {
            $sort = "songs.lwhen DESC";
            $extra = "AND songs.played < 1"; 
        } elsif ($sort == 11) {
            $sort = "songs.lwhen ASC";
            $extra = "AND songs.played < 1"; 
        } elsif ($sort == 12) {
            $sort = "songs.lwhen DESC";
            $extra = "AND songs.played < 1";
            $preface = "SELECT * FROM (";
            $appendage = ") as temp ORDER BY tracknum"; 
        } else {
            $sort = "rand()";
        }
        my $limit = numeric_user_input("How many (default 10)?\n",10);
        my $sql;
        my $select= "SELECT songs.file, songs.song, artists.artist, songs.album, songs.tracknum, songs.songid";
        if ($comp =~ 'y') {
            $sql  = $preface . $select .
                " from songs, artists, albumartist as aa WHERE artists.artist LIKE ? AND aa.albumid = songs.albumid" .
#                $no_chirp .
                $not_long . 
                " AND artists.artistid = aa.artistid AND songs.album LIKE ? and songs.song LIKE ? AND songs.songid" .
                " NOT IN (SELECT songid from songflag WHERE flagid = 5) $extra GROUP BY songs.songid ORDER BY $sort LIMIT ?" .
                $appendage;
        } else { 
            $sql = $preface . $select .
                " from songs, songartist as sa, artists WHERE artists.artist LIKE ? AND artists.artistid = sa.artistid" .
 #               $no_chirp .
                $not_long .
                " AND sa.songid = songs.songid AND songs.album LIKE ? and songs.song LIKE ? AND songs.songid NOT IN (SELECT" .
                " songid from songflag WHERE flagid = 5) $extra GROUP BY songs.songid ORDER BY $sort LIMIT ?" . 
                $appendage;
        }
        print "Query: $sql\n" if ($opt{d});
        my $sth = $dbh->prepare($sql);
        $sth->execute($artist,$album,$song,$limit) or die "Cannot execute... " . $sth->errstr();
        my $done;
        if ($sth->rows > 0) {
            my $count =1;
            while (my @row = $sth->fetchrow_array) {
                print Dumper(\@row) if ($opt{d});
                push (@playlist, [$row[0], $row[5]]);
                print "$count: ($row[4])  $row[1] by $row[2] from $row[3]\n";
                $count++;
            }
            $done = numeric_user_input("Look good? 1. Continue.  2. Search again.\n",1,2);
        } else {
            $done = numeric_user_input("Nothing found. 1. Try again. 2. Quit.\n",1,2);
            if ($done == 1) {
                $done=2;
            } else {
                print "OK, quitting.\n";
                exit;
            }
        }
        undef @playlist if ($done ==2);
        $sth->finish();
    }
    return @playlist;
}

sub pick_one { # Returns an AoA (yes, with only 1 row) of filename and songid sets 
    my ($dbh,$dnp,$mode,$limit_length,$dnpflag) = @_;
            # my $dnp = numeric_user_input("1) Respect or or 2) Ignore DO Not Play flag?\n",1,2);
            # my $mode = numeric_user_input("1) Play any track? or 2) Play only unplayed tracks?\n",1,2);
            # Add mode 3 - Not played recently? What is 'recent'? 
            # my $limit_length = numeric_user_input("Limit song length? 1) Only < 10 minutes 2) Only < 20 minutes 3) Only < 1 hour 4) Unlimited\n",1,4);
    $dnpflag=5 unless $dnpflag;
    $dnp = 1 unless $dnp;
    $mode = 1 unless $mode;
    $limit_length = 1 unless $limit_length;
    my $where = '';
    my $and = '';
    if ($dnp == 1) {
        $where = " songid NOT IN (SELECT songid from songflag WHERE flagid = $dnpflag) ";
        $and = ' AND ';
    }
    if ($mode == 2) {
        $where = $where . $and . ' played = 0 ';
        $and = ' AND ';
    } elsif ($mode == 3) {
        $where = $where . $and . " pwhen < DATE_SUB(NOW(), INTERVAL 6 MONTH) ";# Leaving this off for now to mix in SOME unplayed tracks.    # AND played > 0 ";
        $and = ' AND ';
    }    if ($limit_length == 1) {  # 10 minutes
        $limit_length = ' length < 600 ';
    } elsif ($limit_length == 2) { # 20 minutes
        $limit_length = ' length < 1200 ';
    } elsif ($limit_length == 3) { # 60 minutes
        $limit_length = ' length < 3600 ';
    } else {
        $limit_length = '';
        $and = '';
    }
    $where = $where . $and . $limit_length;
    $where = ' 1 ' unless $where;
    my @playlist;
    #loop until we get a playlist we're happy with.
    until (@playlist) {
        my $sql = "SELECT file, songid FROM songs WHERE " .
            $where .
           " ORDER BY rand() LIMIT 1";
        print "Query: $sql\n" if ($opt{d});
        my $sth = $dbh->prepare($sql);
        print ". . .  (Jesus drives slow) . . . \n" if $opt{'v'};
        $sth->execute() or die "Cannot execute... " . $sth->errstr();
        my $done;
        if ($sth->rows > 0) {
            while (my @row = $sth->fetchrow_array) {
                print Dumper(\@row) if ($opt{d});
                push (@playlist, [$row[0], $row[1]]);
#                print "($row[4])  $row[1] by $row[2] from $row[3]\n";
            }
        } else {
            warn "Failed to find ANYTHING to play. Trying something different.";
            @playlist = pick_one(($dbh,$dnp,3,$limit_length,$dnpflag));
        }
        $sth->finish();
    }
    return @playlist;
}


sub calliope_lists {
    my ($dbh) = @_;
    my @playlist;
    #loop until we get a playlist we're happy with.
    until (@playlist) {
        my $sql = "SELECT listid, list, description FROM lists ORDER BY listid";
        print "Query: $sql\n" if ($opt{d});
        print "Calliope Lists:\n";
        print "No.  Name                    Description\n";
        print "===  ==========              ===========\n";
        my $sth = $dbh->prepare($sql);
        $sth->execute() or die "Cannot execute... " . $sth->errstr();
        $sth->bind_columns(\my($listid,$name,$desc));
        while (my @row = $sth->fetchrow_array) {
            $~ = "LISTS";
            write(STDOUT);
                
format LISTS =
@<<  @<<<<<<<<<<<<<<<<<<<    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$listid, $name, $desc
.
        }

        print "\nLoad which list?\n";
        my $load_list = <STDIN>;
        chomp($load_list);
        $sql = "SELECT songs.file, songs.song, artists.artist, songs.album, songs.tracknum, songs.songid
                    from songs, songartist as sa, artists, listelement as le 
                    WHERE le.type LIKE 'song' AND le.listid = ? AND 
                    le.elementid = songs.songid AND artists.artistid = 
                    sa.artistid AND sa.songid = songs.songid 
                    ORDER BY le.playorder";
        print "Query: $sql\n" if ($opt{d});
        $sth = $dbh->prepare($sql);
        $sth->execute($load_list) or die "Cannot execute... " . $sth->errstr();
        my $counter=1;
        while (my @row = $sth->fetchrow_array) {
            #print Dumper(\@row) if ($opt{d});
            push (@playlist, [$row[0], $row[5]]);
            print "$counter) ($row[4]) $row[1] by $row[2] from $row[3]\n";
            $counter++;
        }


        my $done = numeric_user_input("Look good? 1. Continue  2. Load a different list.\n",1,2);
        undef @playlist if ($done ==2);

        $sth->finish();
    }
    return @playlist;


}

sub playlist_to_db {   #$mode is 1. prepend 2. append 3. replace 4. shuffle (experimental Added 3/24/2016)  Mode 14 = Shuffle but suppress displaying new list.
    my ($mode,@playlist) = @_;
    my @localplaylist;
    # 0) pull only songid from playlist AoA
    for my $i (0 .. $#playlist) {
        push (@localplaylist, $playlist[$i][1]);
    }
    #Prepend = 1) 2) 3) 5) 
    #Append 4) 5)
    #Replace 3) 5) 
    #Shuffle = 1) 2) 3) 6) 5) 
    my $playorder = 1;
    my $display;
    if ($mode == 14) {
        $mode -= 10;
        $display--;
    }
    if (($mode == 1) or ($mode == 4)) {
        $display++;
        #1) read db_playlist
        my $db_playlist =  $dbh->selectall_arrayref("SELECT elementid FROM listelement WHERE listid = $opt{listid} ORDER BY playorder",  { Slice => {}}); #Need "slice?" 
        foreach (@$db_playlist) {
            #2) @playlist = (@playlist, @db_playlist)
            push (@localplaylist, $_->{elementid});
        }
        print Dumper @localplaylist if $opt{d};
    }
    unless ($mode == 2) {
        #3) clear db_playlist
        $dbh->do("DELETE from listelement WHERE listid = $opt{listid} AND elementid != $opt{killcode}");   
    }
    if ($mode == 2) {
        #4) get maxplayorder
        ($playorder) = $dbh->selectrow_array("SELECT max(playorder) from listelement WHERE listid = $opt{listid}");
        $playorder++;
    } 
    if ($mode == 4) {
        #6) Shuffle!
        @localplaylist = shuffle(@localplaylist);
    }
    #5) playlist to db with incremental playorder
    foreach (@localplaylist) {
        print "Adding $_ to database playlist $opt{listid}, playorder $playorder.\n" if $opt{d};
        $dbh->do("INSERT INTO listelement (listid, elementid, type, playorder, uzer) VALUES ( '$opt{listid}', '$_', 'song', '$playorder', 'mmatula') ");
        $playorder++;
    }
    if ($display) {
        display_playlist_by_songid($dbh, @localplaylist);
        print "\n\n";
    }
}


sub display_playlist_by_songid {   # Array is list of songids only. 
    my ($dbh,@playlist) = @_;
#    my $watchthis=1;
    my $dis_count =1;
    my $sth = $dbh->prepare('SELECT songs.song, artists.artist, songs.album, songs.tracknum, 
                    songs.picked from songs, songartist as sa, artists 
                    WHERE songs.songid = ? AND artists.artistid = 
                    sa.artistid AND sa.songid = songs.songid LIMIT 1');
    foreach my $id (@playlist) {
    #    my $id = $playlist[$i][0] ;
        my @row = $dbh->selectrow_array($sth,undef,$id); 
        unless (@row) { die "No result returned."}
        print "$dis_count: ($row[3])  $row[0] by $row[1] from $row[2] picked $row[4] times.\n";
        $dis_count++;
    }
    $sth->finish;
}

sub display_playlist {   # Array is list of filename/songid pairs. 
    my ($dbh,@playlist) = @_;
    my $dis_count =1;
    my $sth = $dbh->prepare('SELECT songs.song, artists.artist, songs.album, songs.tracknum, 
                    songs.picked from songs, songartist as sa, artists 
                    WHERE songs.file = ? AND artists.artistid = 
                    sa.artistid AND sa.songid = songs.songid LIMIT 1');
    for my $i (0 .. $#playlist) {
        my $filename = $playlist[$i][0] ;
        my @row = $dbh->selectrow_array($sth,undef,$filename); 
        unless (@row) { die "No result returned."}
        print "$dis_count: ($row[3])  $row[0] by $row[1] from $row[2] picked $row[4] times.\n";
        $dis_count++;
    }
    $sth->finish;
}

sub display_db_playlist {
####### NOTE: To display playlist: SELECT le.elementid, songs.song, le.playorder FROM listelement as le, songs WHERE listid = $opt{listid} AND le.elementid = songs.songid ORDER BY le.playorder DESC;
        my ($dbh,$no_of_songs_to_display, $offset,$first_or_last, %opt) = @_;
        my $sql = "SELECT le.elementid, songs.song, songs.album, le.playorder, le.le_key FROM listelement as le, songs  WHERE listid = $opt{listid} AND le.elementid = songs.songid ORDER BY le.playorder ASC";
        my %results_hash;
        $sql .= " LIMIT $offset, $no_of_songs_to_display" if ($no_of_songs_to_display || $offset);
        print "Query: $sql\n" if ($opt{d});
#        print "=======================================================================\n";
        print "Database Playlist - $first_or_last $no_of_songs_to_display starting at $offset:\n\n";
        print "SongID       Name/\n";
        print "Play Order   Artist(s),  Album\n";
        print "===========  ==========================================================\n";
        my $sth = $dbh->prepare($sql);
        $sth->execute() or die "Cannot execute... " . $sth->errstr();
        $sth->bind_columns(\my($songid,$name,$album, $order, $key));
        while (my @row = $sth->fetchrow_array) {
                my $artists = join(', ', get_artist_info ($dbh, $songid));
                $results_hash{$songid} = {
                    song => $name,
                    album => $album,
                    artists => $artists,
                    order => $order,
                    key => $key
                };
                $~ = "DBPLAYLIST";
                write(STDOUT);
                
                
format DBPLAYLIST =
ID: @######  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<...
$songid, $name
@###                by @<<<<<<<<<<<<<... on @<<<<<<<<<<<<<<<<<<<<<<<<...
$order, $artists, $album
.

        }
        return (%results_hash);
}


sub numeric_user_input {
    my ($string,$default,$choice_limit) = @_;
    my $numeric = 0;
    my $result;
    until ($result) {
        print $string;
        $result = <STDIN>;
        chomp($result);
        $numeric = (looks_like_number($result) || ($result eq ''));
        if ($numeric)  {
            $result = $default unless ($result);
            if (($choice_limit) && ($result > $choice_limit)) {
                $result = '' ;
                print "Invalid choice > $choice_limit\n";
            }
        } else { 
            print "Non-numeric input. Try again.\n";
            $result = '';
        }
    }
}

sub find_scrobbles {
    my ($songid, $dbh, $mbid, %opt) = @_;
    my ($last_data , $track, $artist, @artists);
    if ($mbid) {
        try  { $last_data = $opt{lastfm}->request( method => 'track.getInfo', username => 'OblivionRatula', mbid => $mbid , format=> 'json' ); }
        catch { warn "No results returned from Last.FM for MBID: $mbid\n" };
        return unless ($last_data);
    } else {
        # Read song info from db
        my $query = "SELECT songs.song, artists.artist FROM `songs`, `artists`, songartist WHERE songs.songid = songartist.songid AND artists.artistid = songartist.artistid AND songs.songid = ?";
        my $sth = $dbh->prepare($query);
        $sth->execute($songid) or die "Cannot execute: " . $sth->errstr();
        die("Song returned too few results!  Dying.\n$_\n") if ($sth->rows < 1);
        while (my @row = $sth->fetchrow_array) {
            $track = $row[0];
            push (@artists, $row[1]);
        }
        for my $i ( 0 .. $#artists) {
            $artist=$artists[$i];
            print "Searching by $artist.\n" if $opt{'v'};
            try { $last_data = $opt{lastfm}->request( method => 'track.getInfo', username => 'OblivionRatula', artist => $artist, track => $track, autocorrect => '1', format=> 'json' );}
            catch { warn "No results returned from Last.FM.\n" };
            $mbid = $last_data->{track}{mbid} if ($last_data);
            last if ($mbid);
            print "Came up empty.\n" if $opt{'v'};
            if ($i == $#artists) { # If we're still in here and haven't gotten a result yet, get desperate
                $artist = join(' ', @artists);
                print "Getting desperate, now searching by $artist.\n" if $opt{'v'};
                try { $last_data = $opt{lastfm}->request( method => 'track.getInfo', username => 'OblivionRatula', artist => $artist, track => $track, autocorrect => '1', format=> 'json' );}
                catch { warn "No results returned from Last.FM.\n" };
                $mbid = $last_data->{track}{mbid} if ($last_data);
                last if ($mbid);
                #Still no? 
                $artist = join(' ', reverse(@artists));
                print "Still nothing, swapping order: $artist\n" if $opt{'v'};
                try { $last_data = $opt{lastfm}->request( method => 'track.getInfo', username => 'OblivionRatula', artist => $artist, track => $track, autocorrect => '1', format=> 'json' );}
                catch { warn "No results returned from Last.FM.\n" };
                $mbid = $last_data->{track}{mbid} if ($last_data);
                last if ($mbid || !$opt{p});
                $artist = join(' ', @artists);
                print ". . . searching for $artist.\n" if $opt{'v'};
                my $last_search;
                try { $last_search = $opt{lastfm}->request( method => 'track.search', username => 'OblivionRatula', track => "$track $artist", format=> 'json' );}
                catch { warn "No results returned from Last.FM.\n" };
                my $break = 1;
                my $results;
                if ($last_search->{results}{trackmatches} =~ /\n/ ) {
                    return # No results.
                } else {
                    $results = $last_search->{results}{trackmatches}{track} ;
                }
                return if ($results =~ /HASH/);
                foreach (@$results) {
                    $mbid = $_->{mbid};
                    if ($mbid) {
                        print "Possible mbid: $mbid\n if $opt{'v'}";
                        try  { $last_data = $opt{lastfm}->request( method => 'track.getInfo', username => 'OblivionRatula', mbid => $mbid , format=> 'json' ); }
                        catch { warn "No results returned from Last.FM.\n" };
                        my $count = $last_data->{track}{userplaycount};
                        my $append;
                        $artist = $last_data->{track}{artist}{name};
                        $track = $last_data->{track}{name};
                        if ($count) { $append = ", Plays: $count\n" } else {$append = ".\n"}
                        print "Does this look valid?\n$artist, $track" .$append;
                        my $done = numeric_user_input("Look good? 1. Yes  2. Search again.\n",1,2);
                        last if ($done ==1);
                        $mbid = undef;
                    }
                    last if ($mbid);
                }
            }
        }    
            
        return unless ($last_data);
    }
#    print Dumper \$last_data;
    my $scrobbles = $last_data->{track}{userplaycount};
    $scrobbles = 0 if (!$scrobbles);
    if ($mbid) {
#        print "We have MBID:\nUPDATE songs SET mbid = '$mbid' , lastFMscrobbles = $scrobbles WHERE songid = $songid \n";
        $dbh->do("UPDATE songs SET mbid = '$mbid' , lastFMscrobbles = $scrobbles WHERE songid = $songid ");
    } else {
 #       print "We have not MBID:\nUPDATE songs SET mbid = NULL , lastFMscrobbles = $scrobbles WHERE songid = $songid\n";
        $dbh->do("UPDATE songs SET mbid = NULL , lastFMscrobbles = $scrobbles WHERE songid = $songid ");
        $mbid = "No MBID found!";   # Missing MBID doens't mean it's nto scrobbable, it just doesn't have a Music Brainz ID assigned.
    }
    print "Scrobbled $scrobbles times." if ($scrobbles);
    print "\n";
    return ($mbid, $scrobbles);
}


sub file_to_songid {   #Unfinished - do I need this?  Yes!!! for if @{$playlist[1]} is not set e.g. -o mode or -f mode
    my ($dbh, $filename, %opt) = @_;
    my $sth = $dbh->prepare("Select songid FROM songs WHERE file = ?");
    my ($songid) = $dbh->selectrow_array($sth, undef, $filename);
    return $songid;
}

sub help {
    my ($message) = @_;
    print "\n$message\n\n";
    print "Plays a playlist of filenames, submits to Last.FM and accounts plays in Calliope db\n";
    print "Modes of operation:\n";
    print " -a = abort! - Not really , but I'm running out of letters. Inserts a stop-plag into DB playlist to die after the current song.\n";
    print " -c = calliope mode - plays from playlist in DB ***\n";
    print " -e = export - IN PROGRESS - for now just displays next 10 songs. ***\n";
    print " -f = filename of playlist of full paths ***\n";
    print " -l = Load a list from Calliope) ***\n";
    print " -j = jukebox mode - Just play a song at a time at random.\n";
    print " -o = one song from a file, by filename (instead of a playlist) ***\n";
    print " -s = search database for songs ***\n\n";
    print "Other options:\n";
    print " -d = debug\n";
    print " -h = this help\n";
    print " -k = keep the database player alive even if the queue is empty.\n";
    print " -p = prompt to confirm MBID finds - otherwise will not attempt deeper search.\n";
    print " -r = randomize/shuffle playlist\n";
    print " -v = verbose\n";
    print " -x = show recently played tracks\n";
    print " *** Also see script itself for important settings. ***\n";
    exit
}

sub init_lastfm {
    my ($opt_hashref) = @_;
    $$opt_hashref{lastfm} = Net::LastFM->new(
        api_key => $$opt_hashref{last_api_key},
        api_secret => $$opt_hashref{last_api_secret}
    );
    return;
}

sub my_connect {
    my ($dsn, %opt) = @_;
    my $dbh= DBI->connect($dsn,$opt{dbuser},$opt{dbpass}) 
        || die "Could not connect to database: $DBI::errstr";
    return $dbh;
}

sub parse_seconds {
  my $seconds = shift;
  my $hours = int( $seconds / (60*60) );
  my $mins = ( $seconds / 60 ) % 60;
  my $secs = $seconds % 60;
  if ($hours) {
      return sprintf("%02d:%02d:%02d", $hours,$mins,$secs);
  } else {
      return sprintf("%02d:%02d", $mins,$secs);
  }
}

sub get_artist_info {
    my ($dbh, $songid) = @_;
    my $query = "SELECT artists.artist " .
                " from songs, songartist as sa, artists WHERE artists.artistid = sa.artistid" .
                " AND sa.songid = songs.songid  AND songs.songid = ? ";
    my $sth=$dbh->prepare($query);
    $sth->execute($songid);
    my @artists;
    while (my @row = $sth->fetchrow_array) {
        push @artists, $row[0];
    }
    $sth->finish;
    return @artists;
}

sub check_filepath {
    my (%opt) = @_;
    if (! -e "$opt{path_mod}/mp3") {
        print "Modified path $opt{path_mod} does not seem to be right.\nCheck your settings in: $opt{cfgfile}\n";
        if ($opt{s}) {
            print "We'll continue since you're just searching, but I wouldn't try to play anything if I were you.\n";
        } else {
            die "It's best not to continue.\n";
        }
    }

}
