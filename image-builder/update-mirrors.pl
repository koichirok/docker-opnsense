#!/usr/bin/env perl

use strict;
use warnings;
use XML::Simple;
use LWP::Simple;
use File::Basename;
use File::Spec;

my $url = "https://raw.githubusercontent.com/opnsense/core/master/src/opnsense/mvc/app/models/OPNsense/Core/repositories/opnsense.xml";
my $mirros_file = File::Spec->catfile(dirname(__FILE__), 'src', 'mirrors.txt');

my $xml = get($url);
my $data = XMLin($xml);

open(my $fh, '>', $mirros_file) or die "Could not open file '$mirros_file' $!";
for my $mirror (@{$data->{mirrors}->{mirror}}) {
    next if ref $mirror->{url};
    $url = $mirror->{url};
    $url .= '/' unless $url =~ m{/$};
    print $fh "$url\n";
}
close $fh;
 