package TieFilehandle;
use Data::Dumper;

use strict;
use Carp;
use Encode;

use constant LAST_BLOCK_MASK => 1 << 31;
use constant BLOCK_TYPE_MASK => 127 << 24;
use constant META_LEN_MASK => 255 + 256*255 + 256*256*255;

my $Debug = 1;

sub create_vorbis_string {
    use utf8;
    my $class = shift;
    my $taghash = shift;
    my $tagstring = '';
    my $vendor = delete($taghash->{'vendor'}) || 'Flac::TieFilehandle';
    # а может быть не L?
    $tagstring .= pack "L",bytes::length($vendor);
    $tagstring .= encode('utf-8', $vendor);
    $tagstring .= pack "L",scalar(keys %$taghash);

    foreach my $key (keys %$taghash) {
        # в перле совершенно непонятный механизм работы с кодировками
        #my $tag = encode('utf-8',$key.'='.$taghash->{$key});
        my $tag = encode('UTF-8',decode('utf8',$key.'='.$taghash->{$key}));
        $tagstring .= pack "L",bytes::length($tag);
        $tagstring .= $tag;#encode('UTF-8',$tag);
    }
    # в метаинформации FLAC у Vorbis Comment не должен быть замыкающий
    # бит, равный 1
    #$tagstring .= pack "b",'1';
    return $tagstring;
}

sub TIEHANDLE {
    my $class = shift;
    my $flac_file = shift;
    open my $self,'<',$flac_file
        or croak sprintf("can't open %s: %s",$flac_file,$!);
    bless $self, $class;
    $$self->{new_vorbis_string} = 
        TieFilehandle->create_vorbis_string(shift);
        #shift;
    $$self->{flac_file} = $flac_file;

    binmode $self;
    # Проверяем, действительно ли открыт файл FLAC
    read $self, my $flac_indicator,4 or croak "Coldn't read file: ".$self->{flac_file};
    if ($flac_indicator ne "fLaC")
    {
        close $self;
        croak "File isn't FLAC: ".$$self->{flac_file};
    }

    # TODO: Сделать ограничние на случай если не найден последний блок
    # метаинформации
    while(1)
    {
        my $begin_of_meta_block = tell($self);

        read $self, my $tmp, 4
            or croak "Coldn't read metadata header in file: ".$self->{flac_file};
        my $meta_head = unpack "N",$tmp;

        # What's the info stored here?
        my ($meta_last,$meta_type,$meta_size);
        $meta_last = (LAST_BLOCK_MASK & $meta_head)>>31;
        $meta_type = (BLOCK_TYPE_MASK & $meta_head)>>24;
        $meta_size = META_LEN_MASK & $meta_head;

        read $self,my $meta_contents,$meta_size 
            or croak "Coldn't read metadata block in file: ".$self->{flac_file};

        my $end_of_meta_block = tell($self);

        if ($meta_type==4)
        {
            # This is The Vorbis tag
            $$self->{'vorbis_comment'} = {
                # meta_size - without header of block
                'meta_size' => $meta_size,
                'begin' => $begin_of_meta_block,
                'end' => $end_of_meta_block,
                'content' => $meta_contents
            };
            $$self->{'vorbis_comment'}{'meta_last'} = 1 if $meta_last;
        }

        if ($meta_type==1)
        {
            $$self->{'padding'} = {
                # meta_size - without header of block
                'meta_size' => $meta_size,
                'begin' => $begin_of_meta_block,
                'end' => $end_of_meta_block
            };
            $$self->{'padding'}{'meta_last'} = 1 if $meta_last;
        }

        if ($meta_last)
        {
            last;
        }
    }

    # Формирование нового заголовка для meta-vorbis
    # Сомнительная конструкция - заменить
    my $meta_vorbis_head = $$self->{'vorbis_comment'}{'meta_last'}<<31;# последний ли блок
    $meta_vorbis_head |= 4<<24;#идентификатор vorbis meta = 4
    $meta_vorbis_head |= bytes::length($$self->{new_vorbis_string});
    $$self->{new_vorbis_string} = (pack "N",$meta_vorbis_head) . $$self->{new_vorbis_string};

    if (my $inforef = shift) {
        %$inforef = (
                'old_vorbis_length' => 
                    $$self->{'vorbis_comment'}{'end'} - $$self->{'vorbis_comment'}{'begin'},
                'new_vorbis_length' => 
                    bytes::length($$self->{new_vorbis_string})
        )
    }

    #print STDERR Dumper $$self->{new_vorbis_string};
    seek $self,0,0;

    #$$self->{overflow} = '1234567890'x24;

    return $self;
}

sub CLOSE {
    my $self = shift;
    return close $self;
}

sub TELL {
    my $self = shift;
    return $$self->{position}||0;
}

sub SEEK {
    my ($self, $position, $whence) = @_;
    if ($whence == 0) {
        $$self->{position} = $position;
    }
    elsif ($whence == 1) {
        $$self->{position} += $position;
    }
    elsif ($whence == 2) {
        die "error to set pointer from EOF\n";
        #TODO: сделать рассчет от конца файла.
        #return 0 if $position > 0;
        #$$self->{position} += $position;
    }
}

sub READ {
    my ($self, undef, $length, $offset) = @_;
    my $bufref = \$_[1];

    # указатель в мнимом файле
    my $position = $$self->{position};

    my $vorbis_begin = $$self->{'vorbis_comment'}{'begin'};
    my $vorbis_end = $$self->{'vorbis_comment'}{'end'};
    my $old_meta_len = $vorbis_end-$vorbis_begin;
    my $new_meta_len = bytes::length($$self->{new_vorbis_string});

    if ($position<$vorbis_begin) {
        seek ($self,$position,0);
    }
    elsif ($position=>$vorbis_begin && $position<$vorbis_end-$old_meta_len+$new_meta_len) {
        seek ($self,$vorbis_end,0);
    }
    else {
        seek ($self,$position-$new_meta_len+$old_meta_len,0);
    }

    my $cur_buflen = bytes::length($$bufref);
    while ($cur_buflen<$length) {
        my $cur_position = $position + $cur_buflen;

        if (($cur_position+$cur_buflen)<$vorbis_begin) {
            read($self, $$bufref, ($length-$cur_buflen>$vorbis_begin-$cur_position)?$vorbis_begin-$cur_position:$length-$cur_buflen), $cur_buflen;
        }
        elsif ($cur_position>=$vorbis_begin && $cur_position<$vorbis_begin+$new_meta_len) {
            $$bufref .= bytes::substr($$self->{new_vorbis_string},$cur_position-$vorbis_begin,$length-$cur_buflen);
        }
        elsif ($cur_position=>$vorbis_begin+$new_meta_len) {
            seek ($self,$vorbis_end,0) if tell($self)==$vorbis_begin;
            last if !read($self, $$bufref, $length-$cur_buflen, $cur_buflen);
        }
        $cur_buflen = bytes::length($$bufref);
    }

    $$self->{position} = $position+$cur_buflen;
    return $cur_buflen;
}

#package main;
#use Data::Dumper;
#
#my $new_vorbis_taghash = {
#    'vendor' => 'test_vendor',
#    'artist' => 'test_artist',
#};
#
#my $flacfile = shift;
#my $flachandler = *FLACFILE;
#tie *$flachandler, "TieFilehandle", $flacfile, $new_vorbis_taghash;
#while (my $status = (read $flachandler,my $buffer, 32)) {
#    print $buffer;
#    #print bytes::length($buffer)."\n"
#}
