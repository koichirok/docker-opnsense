#!/usr/bin/env perl

use strict;
use warnings;
use LWP::Simple;

my $abi = "FreeBSD:13:amd64";
my $series = "24.1";

while (<>) {
    chomp;
    my $mirror = $_;
    $mirror =~ s|/releases/.*|/|;
    print "$mirror ";
}