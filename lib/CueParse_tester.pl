#!/usr/bin/perl
use FindBin;
use lib "$FindBin::RealBin";

use Data::Dumper;

use strict;
use CueParse2;

my $cueFile = shift;
my $cue = parseCue($cueFile) or die "неверный $cueFile";
print Dumper $cue;
