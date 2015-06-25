#!/usr/bin/perl
use strict;
use warnings;

use DBI;
use Data::Dumper;
use Audio::MPD;

my $db = DBI->connect("dbi:SQLite:dbname=/home/noname/play_stat.db","",
    "", { RaiseError => 1, AutoCommit => 1 } );
#установка режима юникод
$db->{sqlite_unicode} = 1;
#создание таблиц
# TODO: дописать автоитератор
$db->do(<<'__SQL_END__') or die($db->errstr);
CREATE TABLE IF NOT EXISTS artist (
    artist_id INTEGER PRIMARY KEY,
    name VARCHAR( 255 ) NOT NULL
)
__SQL_END__

$db->do(<<'__SQL_END__') or die($db->errstr);
CREATE TABLE IF NOT EXISTS album (
    album_id INTEGER PRIMARY KEY,
    artist_id INT NOT NULL,
    title VARCHAR( 255 ) NOT NULL,
    orig_year SMALLINT NOT NULL,
    release_year SMALLINT NOT NULL,
    FOREIGN KEY (artist_id) REFERENCES album(artist_id)
    ON DELETE RESTRICT
)
__SQL_END__

$db->do(<<'__SQL_END__') or die($db->errstr);
CREATE TABLE IF NOT EXISTS track (
    track_id INTEGER PRIMARY KEY,
    album_id INT NOT NULL,
    track_num SMALLINT NOT NULL,
    title VARCHAR( 255 ) NOT NULL,
    length INT NOT NULL,
    disc SMALLINT,
    FOREIGN KEY (album_id) REFERENCES album(album_id)
    ON DELETE RESTRICT
)
__SQL_END__

$db->do(<<'__SQL_END__') or die($db->errstr);
CREATE TABLE IF NOT EXISTS play_log (
    track_id INTEGER PRIMARY KEY,
    time DATETIME NOT NULL,
    FOREIGN KEY (track_id) REFERENCES track(track_id)
    ON DELETE RESTRICT
)
__SQL_END__

my $mpd = Audio::MPD->new;
my $collection = $mpd->collection;

my $get_artist_id = $db->prepare(<<'__SQL_END__');
SELECT artist_id FROM artist WHERE name = ?
__SQL_END__

my $get_album_id = $db->prepare(<<'__SQL_END__');
SELECT album_id FROM album WHERE artist_id = ?
    and title = ? and release_year = ?
__SQL_END__

my $get_track_info = $db->prepare(<<'__SQL_END__');
SELECT track_id, title, length FROM track WHERE album_id = ?
    and track_num = ? and disc = ?
__SQL_END__

my $add_artist = $db->prepare(<<'__SQL_END__');
INSERT INTO artist ( artist_id, name ) 
    VALUES ( null, ? )
__SQL_END__

my $add_album = $db->prepare(<<'__SQL_END__');
INSERT INTO album (album_id, artist_id, title, orig_year, release_year) 
    VALUES ( null, ?, ?, ?, ? )
__SQL_END__

my $add_track = $db->prepare(<<'__SQL_END__');
INSERT INTO track (track_id, album_id, track_num, disc, title, length) 
    VALUES ( null, ?, ?, ?, ?, ? )
__SQL_END__

my $update_track = $db->prepare(<<'__SQL_END__');
UPDATE track SET title = ? WHERE track_id = ?
__SQL_END__

# TODO: предусмотреть изменение названия исполнителя в коллекции
# все нижеследующее происходит в пределах одного исполнителя
foreach my $artist ( sort($collection->all_artists) ) {
    # если не задано название исполнителя, пропустить
    next unless $artist;
    $get_artist_id->execute($artist);
    # может быть загвоздка с разными исполнителями имеющими
    # одинаковые названия
    my @row = $get_artist_id->fetchrow_array;
    my $artist_id;
    $artist_id = $row[0] if $row[0];
    unless ($artist_id) {
        # если испольнитель с таким названием не существует в базе,
        # добавляем его
        $add_artist->execute($artist);
        $artist_id = $db->last_insert_id(undef,undef,undef,undef);
    }

    # не используется $collection->albums_by_artist( $artist ), потому
    # как нужно извлечь с названием альбома также год его выпуска
    my @songs = $collection->songs_by_artist($artist);
    my %seen = ();
    my @albums = ();
    # выделяю из массива песен @songs, массив неповторяющихся альбомов
    # в пределеах одного исполнителся
    foreach my $song ( @songs ) {
        next if not ( $song->date =~ m/(\d{4})(?:-(\d{4}))?/ 
                and $song->album );
        unless ($seen{$song->date,"\0",$song->album}++) {
            my %entry = ();
            $entry{orig_year} = $1;
            $entry{release_year} = $2 || $1;
            $entry{title} = $song->album;
            push(@albums,\%entry);
        }
    }

    foreach my $album (@albums) {
        # используется алгоритм, похожий на добавление исполнителя
        $get_album_id->execute($artist_id,$album->{title},
            $album->{release_year});
        my @row = $get_album_id->fetchrow_array;
        my $album_id;
        $album_id = $row[0] if $row[0];
        unless ($album_id) {
            $add_album->execute($artist_id,$album->{title},
                $album->{orig_year},$album->{release_year});
        }
        # TODO: учесть, что может смениться только название альбома
    }

    foreach my $song ( @songs ) {
        $song->date =~ m/(\d{4})(?:-(\d{4}))?/;
        my $release_year = $1 || $2;
        $get_album_id->execute( $artist_id, $song->album, $release_year);
        my @row = $get_album_id->fetchrow_array;
        next unless @row;
        my $album_id = $row[0];
        $get_track_info->execute( $album_id, $song->track,
            $song->disc||1);
        my $row = $get_track_info->fetchrow_hashref;
        #если в данном альбоме уже существует трек с данным номером
        if (%$row) {
            #если изменилось название одного из треков, обновить его.
            $update_track->execute($song->title,$row->{track_id})
                if $row->{length} == $song->time and
                    $row->{title} ne $song->title;
        }
        else {
            $add_track->execute($album_id,$song->track,$song->disc||1,
                $song->title, $song->time);
        }
    }
}


$db->disconnect;
