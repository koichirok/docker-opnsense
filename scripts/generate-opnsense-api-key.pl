#!/usr/bin/env perl

use strict;
use warnings;
use WWW::Mechanize ();
use Getopt::Std;
use HTML::TreeBuilder;

my %opts = (
    H => "192.168.1.1",                     # OPNsense IP address
    u => "root",                            # OPNsense username
    p => "opnsense",                        # OPNsense password
    f => "/root/.opnsense-api-key.json",    # Output file
);
getopts('H:u:p:f:', \%opts);

sub trim {
    my $str = shift;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

sub trim_and_unquote {
    my $str = trim(shift);
    $str =~ s/^(\\?['"])//;
    $str =~ s/$1$//;
    return $str;
}


sub open_system_usermanager {
    my $mech = shift;
    $mech->get("https://$opts{H}/");

    if ($mech->title() eq "Login | OPNsense") {
        $mech->submit_form(
            form_name => 'iform',
            fields    => {
                usernamefld => $opts{u},
                passwordfld => $opts{p},
            },
            button => 'login',
        );
    }
    $mech->get("https://$opts{H}/system_usermanager.php");
    $mech->title() =~ /^Users \| Access \| System \| /
      || die "Failed to open \"System: Access: Users\" page: login failed\n";
}

sub open_system_usermanager_edit_page_for_user {
    my ($mech, $user) = @_;

    my $tree = HTML::TreeBuilder->new_from_content($mech->content());

    # Find the link to edit the $user.
    # These links are in the last column of the table and
    # the user name is in the first column.
    my @links = $tree->look_down(
        _tag => 'a',
        href => qr/system_usermanager\.php\?act=edit&userid=\d+/
    );
    for my $link (@links) {
        my $row = $link->parent->parent;
        next if ($row->tag() ne 'tr');

        my @cells = $row->find_by_tag_name('td');
        next if (trim($cells[0]->as_trimmed_text()) ne $user);

        $mech->get($link->attr('href'));
        return;
    }
    die "Failed to find link to edit user $user\n";
}

sub generate_api_key {
    my $mech = shift;
    $mech->uri() =~ /\buserid=(\d+)/ || die "Failed to find userid in URL\n";
    my $userid = $1;

    my $tree = HTML::TreeBuilder->new_from_content($mech->content());

    my @scripts = map { my @c = $_->content_list(); @c }
      $tree->look_down(_tag => 'script', src => undef);

    # Generating an API key requires simulating an XHR request, as the key is
    # created using JavaScript. OPNsense includes a CSRF token in the
    # X-CSRFToken header with the XHR, which we need to collect and set in the
    # $mech object. As this is the final request in this script, there's no
    # need to reset the headers afterwards.
    for my $script (@scripts) {
        if (ref $script ne '') {
            print STDERR "WARN: Unexpected script content: $script\n";
            next;
        }
        if ($script =~ /setRequestHeader\((.+?),(.+?)\)/mg) {
            my ($name, $value) =
              (trim_and_unquote($1), trim_and_unquote($2));
            $mech->add_header($name, $value);
        }
    }
    $mech->post($mech->uri(), {act => 'newApiKey', userid => $userid});
    $mech->save_content($opts{f});
    print "API key saved to $opts{f}\n";
}

sub main {
    my $mech = WWW::Mechanize->new(
        ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0},);
    open_system_usermanager($mech);
    open_system_usermanager_edit_page_for_user($mech, $opts{u});
    generate_api_key($mech);
    exit 0;
}

main();

1;
