#!/usr/bin/perl
use FindBin;
use lib "$FindBin::RealBin/lib";

use strict;
use DateTime::Cron::Simple;

use DBI;
my $db = DBI->connect("dbi:SQLite:dbname=/home/noname/play_stat.db",
        "","", { RaiseError => 1, AutoCommit => 1 } );

use Audio::MPD;
my $mpd = Audio::MPD->new;
my $mpd_playlist = $mpd->playlist;

use Data::Dumper;
my $cron_checker = DateTime::Cron::Simple->new();

my $line_num = 0;
while (my $line = <DATA>) {
    $line_num++;
    next if $line =~ m/(?:^#)|(?:^\s*$)/;
    $line .= <DATA> while $line =~ s/\\\s*$//;

    die "синтаксическая ошибка в строке $line_num\n"
        unless $line =~ m/((?:[-0-9,*]+\s+){5})(.*)/;

    my ($cron_time, $command) = ($1,$2);
    $cron_checker->new_cron($cron_time);
    if ($cron_checker->validate_time) {
        my $sql = "SELECT count(*) as count FROM ($command)";
        my $sth = $db->prepare($sql);
        printf "время: %s; комманда: %s\n",$cron_time,$sql;
        $sth->execute;
        if ($sth->fetchrow_hashref->{count} > 0) {
            $sql = "SELECT uri FROM ($command)";
            $sth = $db->prepare($sql);
            $sth->execute;
            while ( my $row = $sth->fetchrow_hashref ) {
                print "добавляется ",$row->{uri},"\n";
                $mpd_playlist->add($row->{uri});
            }
            last;
        }
        else {
            warn "запрос не вернул записей, поиск продолжен\n"
        }
    }
}

__DATA__
# строки, начинающиеся со знака '#' считаются комментариями

## в будние дни с 14 часов по 16
## 10 случайных треков
#* 14-16,23 * * 1-5 \
#SELECT * FROM track ORDER BY random() LIMIT 10

## в воскресенье в 20
## 1 случайный альбом
#* 20 * * 7 \
#SELECT uri FROM track \
#WHERE album_id = (SELECT album_id FROM album ORDER BY random() LIMIT 1) \
#ORDER BY disc, track_num

# случайный альбом из 20-ти наиболее прослушиваемых
* * * * * \
SELECT uri FROM track \
WHERE album_id = \
( SELECT album_id FROM \
(SELECT album_id FROM avg_playing_albums ORDER BY avg_playing DESC LIMIT 20) \
ORDER BY random() LIMIT 1 ) \
ORDER BY disc, track_num

## случайный альбом из альбомов, треки которых 
## ниразу не воспроизводились в течение последнего месяца
#* * * * * \
#SELECT uri FROM track \
#WHERE album_id = \
#    ( SELECT me.album_id FROM track as me \
#        WHERE NOT EXISTS \
#            ( SELECT * FROM play_log JOIN track ON play_log.track_id = track.track_id \
#                WHERE track.album_id = me.album_id AND time > datetime('now','-1 month') ) \
#        GROUP BY me.album_id \
#        ORDER BY random() \
#        LIMIT 1 ) \
#ORDER BY disc, track_num



#   *  *  *  *  *      command to be executed
#   -  -  -  -  -
#   |  |  |  |  |
#   |  |  |  |  +----- day of week (0 - 6) (Sunday=0)
#   |  |  |  +---------- month (1 - 12)
#   |  |  +--------------- day of month (1 - 31)
#   |  +-------------------- hour (0 - 23)
#   +------------------------- min (0 - 59)
