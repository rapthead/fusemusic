#!/usr/bin/perl
use strict;
use DateTime;
use DateTime::TimeZone;
use DBI;
use Getopt::Long;
use Data::Dumper;

sub usage { 
        print "$0 [-file путь_к_базе_sqlite] [-debug] [-help] [-verbose [-verbose [..] ] ]\n";
        exit 0;
}

my $local_tz = DateTime::TimeZone->new( name => 'local' );

my ($verbose,$sqlite_file,$debug) = (0);
GetOptions ("file=s" => \$sqlite_file, "debug" => \$debug,
    'verbose' => sub { $verbose++ },
    'help' => \&usage,
) or usage();

if ($sqlite_file) {
    -w $sqlite_file or die "$sqlite_file не доступен на запись\n"
}
my $filename = shift or die "ожидается аргумент\n";
-r $filename or die "$filename не доступен на запись!";
#TODO: проверка

my $db = DBI->connect(
    $sqlite_file ? "dbi:SQLite:dbname=$sqlite_file" : "dbi:SQLite:dbname=/home/noname/play_stat.db",
    '',
    '',
    {RaiseError=>1}
);

my $get_track_id = $db->prepare(<<'__SQL__') or die "$@\n";
    SELECT track.track_id as track_id, count(*) as count FROM track
    JOIN album ON track.album_id = album.album_id
    JOIN artist ON artist.artist_id = album.artist_id
    WHERE 
    artist.name LIKE ? AND
    album.title LIKE ? AND
    track.title LIKE ? AND
    track.track_num = ?
__SQL__

my $is_exist = $db->prepare(<<'__SQL_END__');
SELECT count(*) as count FROM play_log
WHERE track_id = ? AND
strftime('%s',time) = ?
__SQL_END__

my $insert_play_log = $db->prepare(<<'__SQL_END__');
INSERT INTO play_log (track_id,time,source)
VALUES (?, datetime(?,'unixepoch'), 1 )
__SQL_END__

open SCROB,'<',$filename;
while ( my $line = <SCROB> ) {
    print $line if $debug;
    if ($line =~ /^(#.*)?$/) {
        warn "пропуск" if $debug;
        next;
    }
    my ( $artist, $album, $track, $track_num, $duration, $rating, $unixtime ) = split "\t",$line;
    next if $rating ne 'L';

    # перевод из локального epoch в правильный
    my $dt = DateTime->from_epoch( epoch => $unixtime, time_zone => 'floating' ) if $unixtime;
    $unixtime = $dt->set_time_zone($local_tz)->epoch;

    $get_track_id->execute($artist,$album,$track,$track_num) or die $@;
    my $rows = $get_track_id->fetchrow_hashref;
    if ($rows->{count} != 1) {
        warn sprintf("%s-%s-%s не найдена (или неоднозначно определена) композиция\n",$artist, $album, $track);
        next;
    }
    my $track_id = $rows->{track_id};

    $is_exist->execute($track_id,$unixtime) or die $@;
    $rows = $is_exist->fetchrow_hashref;
    if ($rows->{count} != 0) {
        warn sprintf("%s %s %s-%s-%s уже существует\n",$dt->ymd('-'),$dt->hms(':'),$artist, $album, $track)
            if $verbose;
        next;
    }

    $insert_play_log->execute($track_id,$unixtime) or die $@;
}
