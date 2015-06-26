#!/bin/bash
wd=$PWD
tmpdir="/tmp/rgcalc/"
[ -e $tmpdir ] || mkdir -p $tmpdir
find "$wd" -name '*.cue' | sort | while read cue
do
        echo 'processing' $cue

        rm -rf $tmpdir/*
        dir=`dirname "$cue"`
        cd "$dir"
        cp *.flac "$tmpdir"
        metaflac --add-replay-gain $tmpdir/*.flac

        [ -e "$cue.bak" ] || cp "$cue" "$cue.bak"

        cd "$tmpdir"
        for file in *.flac
        do
            metaflac --with-filename \
                --show-tag=REPLAYGAIN_REFERENCE_LOUDNESS \
                --show-tag=REPLAYGAIN_TRACK_GAIN \
                --show-tag=REPLAYGAIN_TRACK_PEAK \
                --show-tag=REPLAYGAIN_ALBUM_GAIN \
                --show-tag=REPLAYGAIN_ALBUM_PEAK "$file"
        done | ~/bin/perl/rg2cue2.pl "$cue" > "$cue.new"

        if [ $? -eq 0 ]; then
            echo 'moving'
            mv "$cue.new" "$cue"
        fi

        cd "$wd"
done
