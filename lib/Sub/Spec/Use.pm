package Sub::Spec::Use;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Sub::Spec::URI;

# VERSION

our %SPEC;

$SPEC{load_ss_module} = {
    summary => 'Load a module specified using Sub::Spec URI',
    result => 'undef',
    description => <<'_',

"Load" a module specified by using Sub::Spec::URI (e.g. pm://Foo::Bar or
http://example.com/Foo::Bar). Actually, what is being done is query the remote
URI for available functions, and for each function, create a proxy (and get its
spec from the URI, if available). The proxy function will then call the remote
function.

_
    args => {
        uri => ['str*' => {
            summary     => 'Location of module',
        }],
        into => ['str' => {
            summary     => 'Package name to put proxy functions into',
            description => <<'_',

Default is to be determined from URI. For example, if URI is pm://Foo::Bar,
then 'into' will be set to 'Foo::Bar'.

_
        }],
    },
};
sub load_ss_module {
    my %args   = @_;
    my $uri    = $args{uri} or return [400, "Please specify uri"];
    my $into   = $args{into};
    $log->tracef("-> load_ss_module(%s)", \%args);

    $uri = Sub::Spec::URI->new($uri) unless ref($uri);

    my $orig = $uri->module or
        return [400, "URI doesn't contain module name"];
    $into //= $orig;
    return [500, "Invalid module name `$into`"]
        unless $into =~ /\A\w+(::\w+)*\z/;

    my @subs = @{$uri->list_subs};
    my @loaded;
    for my $sub (@subs) {
        unless ($sub =~ /\A\w+\z/) {
            $log->error("Can't load sub `$sub`: invalid name");
            next;
        }
        push @loaded, $sub;
        no strict 'refs';
        *{"$into\::$sub"} = sub {
            # XXX what if server uri is not pm?
            # XXX original uri's args?
            $uri->call_other({uri=>"pm://$orig/$sub"}, @_);
        };
    }

    $log->tracef("<- load_ss_module()");
    [200, "OK", {orig_module=>$orig, module=>$into,
                 subs=>\@subs, loaded_subs=>\@loaded}];
}

sub import {
    my ($module, $uri, @args) = @_;
    my $caller = caller;

    die "import: Please specify URI as first argument" unless $uri;

    my @subs;
    my $i = 0;
    my $into;
    while ($i < @args) {
        if ($args[$i] eq '-into') {
            $into = $args[$i+1];
            $i++;
        } else {
            push @subs, $args[$i];
        }
        $i++;
    }

    my $loaded;
    for my $inc (keys %INC) {
        my $pm = $inc;
        $pm =~ s!/!::!g; $pm =~ s/\.pm$//;
        if ($INC{$inc} eq $uri && (!$into || $into eq $uri)) {
            $loaded++;
            last;
        }
    }
    if ($loaded) {
        $log->("$uri".($into ? " (-into $into)":"")." already loaded, skipped");
        return;
    }

    my $res = load_ss_module(uri=>$uri, into=>$into);
    die "import: Can't load $uri: $res->[0] - $res->[1]"
        unless $res->[0] == 200;

    $into = $res->[2]{module};
    my @avail = @{ $res->[2]{loaded_subs} };
    @subs = @avail if ':all' ~~ @subs;

    for my $sub (@subs) {
        unless ($sub ~~ @avail) {
            die "import: function `$sub` is not available from $uri";
        }
        no strict 'refs';
        *{"$caller\::$sub"} = \&{"$into\::$sub"};
    }

    my $inc = $into;
    $inc =~ s!::!/!g; $inc .= ".pm";
    $INC{$inc} = $uri;

    1;
}

1;
# ABSTRACT: Load a module specified using Sub::Spec URI

=head1 SYNOPSIS

 use Sub::Spec::Use "http://example.com/My::Math" => qw(pyth);
 print pyth(3, 4); # 5

 use Sub::Spec::Use "http://example.com/My::Math" => qw(:all);


=head1 DESCRIPTION

B<NOTICE>: This module and the L<Sub::Spec> standard is deprecated as of Jan
2012. L<Rinci> is the new specification to replace Sub::Spec, it is about 95%
compatible with Sub::Spec, but corrects a few issues and is more generic.
C<Perinci::*> is the Perl implementation for Rinci and many of its modules can
handle existing Sub::Spec sub specs.

This module provides load_ss_module(), usually used as shown in Synopsis, a la
Perl's use().

This module uses L<Log::Any> for logging.


=head1 FUNCTIONS

None are exported.


=head1 TODO

* Can't work with other server URI's except pm://

=head1 SEE ALSO

L<Sub::Spec>

=cut
