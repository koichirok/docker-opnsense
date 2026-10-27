use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP qw(decode_json encode_json);

my $directory = tempdir(CLEANUP => 1);
my $output = "$directory/credentials.json";
local @ARGV = ('-f', $output, '-q');
do "$FindBin::Bin/../src/generate-opnsense-api-key.pl"
    or die $@ || $!;

{
    package MockBrowser;

    sub new {
        my ($class, %options) = @_;
        return bless {
            status => 200, authenticated => 0,
            credentials => {result => 'ok', key => 'test-key', secret => 'test-secret'},
            %options,
        }, $class;
    }
    sub get {
        my ($self, $url) = @_;
        $self->{uri} = $url;
        $self->{status} = $url =~ m{/ui/auth/user/}
            ? ($self->{page_status} // 200) : 200;
    }
    sub submit_form { $_[0]->{authenticated} = !$_[0]->{bad_password} }
    sub title {
        return $_[0]->{authenticated}
            ? 'Users | Access | System | OPNsense' : 'Login | OPNsense';
    }
    sub success { $_[0]->{status} == 200 }
    sub status { $_[0]->{status} }
    sub uri { $_[0]->{uri} }
    sub content {
        my $self = shift;
        return $self->{response} if exists $self->{response};
        return '<html></html>' if $self->{no_csrf};
        return q{<html><script>xhr.setRequestHeader("X-CSRFToken", "test-token");</script></html>};
    }
    sub add_header {
        my ($self, $name, $value) = @_;
        $self->{headers}{$name} = $value;
    }
    sub post {
        my ($self, $url, $fields) = @_;
        $self->{posted_url} = "$url";
        $self->{posted_fields} = $fields;
        $self->{status} = $self->{post_status} // 200;
        $self->{response} = $self->{raw_response}
            // main::encode_json($self->{credentials});
    }
}

my $browser = MockBrowser->new;
ok(open_system_usermanager($browser), 'current user management selected');
generate_api_key($browser, 1);
is($browser->{posted_url}, 'https://192.168.1.1/api/auth/user/add_api_key/root',
    'uses current API endpoint');
is($browser->{headers}{'X-CSRFToken'}, 'test-token', 'sends CSRF header');
is((stat($output))[2] & 0777, 0600, 'credentials are private');
open my $file, '<', $output or die $!;
my $saved = do { local $/; <$file> };
close $file;
is_deeply(decode_json($saved), {key => 'test-key', secret => 'test-secret'},
    'preserves credential output shape');

$browser = MockBrowser->new(page_status => 404);
is(open_system_usermanager($browser), 0, '404 selects legacy user management');
$browser->{uri} = 'https://192.168.1.1/system_usermanager.php?act=edit&userid=0';
generate_api_key($browser, 0);
is_deeply($browser->{posted_fields}, {act => 'newApiKey', userid => 0},
    'preserves legacy key generation request');
open $file, '<', $output or die $!;
$saved = do { local $/; <$file> };
close $file;

for my $case (
    ['login failure', {bad_password => 1}, qr/login failed/],
    ['server failure', {page_status => 503}, qr/current user management/],
) {
    my ($name, $options, $error) = @$case;
    eval { open_system_usermanager(MockBrowser->new(%$options)) };
    like($@, $error, "$name fails explicitly");
}

for my $case (
    ['missing CSRF', {no_csrf => 1}],
    ['HTTP error', {post_status => 403}],
    ['invalid JSON', {raw_response => '<html>Login</html>'}],
    ['invalid object', {raw_response => '[]'}],
    ['rejected request', {credentials => {result => 'failed'}}],
    ['missing secret', {credentials => {result => 'ok', key => 'test-key'}}],
    ['non-scalar secret', {credentials => {result => 'ok', key => 'k', secret => []}}],
) {
    my ($name, $options) = @$case;
    eval { generate_api_key(MockBrowser->new(%$options), 1) };
    ok($@, "$name fails explicitly");
    open my $existing, '<', $output or die $!;
    my $content = do { local $/; <$existing> };
    close $existing;
    is($content, $saved, "$name leaves existing credentials unchanged");
}

done_testing();
