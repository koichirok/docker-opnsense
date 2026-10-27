#!/usr/bin/env perl

use strict;
use warnings;
use WWW::Mechanize ();
use Getopt::Std;
use HTML::TreeBuilder;
use JSON::PP qw(decode_json encode_json);
use File::Temp qw(tempfile);
use File::Basename qw(dirname);
use URI::Escape qw(uri_escape_utf8);

my %opts = (
    H => "192.168.1.1",                     # OPNsense IP address
    u => "root",                            # OPNsense username
    p => "opnsense",                        # OPNsense password
    f => "/root/.opnsense-api-key.json",    # Output file
    q => 0,                                 # Quiet mode
);
getopts('H:u:p:f:q', \%opts);

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
    $mech->success() || die "Failed to open OPNsense login page\n";

    if ($mech->title() eq "Login | OPNsense") {
        $mech->submit_form(
            form_name => 'iform',
            fields    => {
                usernamefld => $opts{u},
                passwordfld => $opts{p},
            },
            button => 'login',
        );
        $mech->success() || die "OPNsense login request failed\n";
    }
    $mech->title() ne "Login | OPNsense"
      || die "OPNsense login failed\n";

    $mech->get("https://$opts{H}/ui/auth/user/");
    if ($mech->status() != 404) {
        $mech->success() || die "Failed to open current user management page\n";
        return 1;
    }

    $mech->get("https://$opts{H}/system_usermanager.php");
    $mech->success() || die "Failed to open legacy user management page\n";
    $mech->title() =~ /^Users \| Access \| System \| /
      || die "Failed to open \"System: Access: Users\" page: login failed\n";
    return 0;
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
        $mech->success() || die "Failed to open user edit page\n";
        return;
    }
    die "Failed to find link to edit user $user\n";
}

sub set_csrf_header {
    my $mech = shift;

    my $tree = HTML::TreeBuilder->new_from_content($mech->content());

    my @scripts = map { my @c = $_->content_list(); @c }
      $tree->look_down(_tag => 'script', src => undef);

    for my $script (@scripts) {
        next if ref $script;
        while ($script =~ /setRequestHeader\((.+?),(.+?)\)/mg) {
            my ($name, $value) =
              (trim_and_unquote($1), trim_and_unquote($2));
            next unless $name eq 'X-CSRFToken' && length $value;
            $mech->add_header($name, $value);
            return;
        }
    }
    die "Failed to find the OPNsense CSRF token\n";
}

sub generate_api_key {
    my ($mech, $modern) = @_;
    set_csrf_header($mech);
    if ($modern) {
        my $username = uri_escape_utf8($opts{u});
        $mech->post("https://$opts{H}/api/auth/user/add_api_key/$username", {});
    } else {
        $mech->uri() =~ /\buserid=(\d+)/ || die "Failed to find userid in URL\n";
        $mech->post($mech->uri(), {act => 'newApiKey', userid => $1});
    }
    $mech->success() || die "API key generation HTTP request failed\n";

    my $credentials = decode_json($mech->content());
    ref($credentials) eq 'HASH'
      || die "API key generation returned an invalid JSON object\n";
    if ($modern) {
        ($credentials->{result} // '') eq 'ok'
          || die "OPNsense rejected API key generation\n";
    }
    for my $field (qw(key secret)) {
        defined($credentials->{$field}) && !ref($credentials->{$field})
          && length($credentials->{$field})
          || die "API key generation returned no $field\n";
    }

    my ($file, $temporary) = tempfile('.opnsense-api-key-XXXXXX',
        DIR => dirname($opts{f}), UNLINK => 1);
    print {$file} encode_json({
        key => $credentials->{key}, secret => $credentials->{secret},
    }) or die "Failed to write API credentials: $!\n";
    close $file or die "Failed to close API credentials: $!\n";
    rename $temporary, $opts{f} or die "Failed to save API credentials: $!\n";
    print "API key saved to $opts{f}\n" unless $opts{q};
}

sub main {
    my $mech = WWW::Mechanize->new(
        autocheck => 0,
        ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0},);
    my $modern = open_system_usermanager($mech);
    open_system_usermanager_edit_page_for_user($mech, $opts{u}) unless $modern;
    generate_api_key($mech, $modern);
    exit 0;
}

main() unless caller;

1;
