use strict;
use warnings;

use DateTime;
use DateTime::TimeZone::Local 1.85;
use File::Basename qw( basename );
use File::Spec;
use Sys::Hostname qw( hostname );
use Test::More;

use lib File::Spec->catdir( File::Spec->curdir, 't' );

plan skip_all => 'These tests only run on Windows'
    unless $^O =~ /win32/i;

my $Registry;
use DateTime::TimeZone::Local::Win32;
use Win32::TieRegistry 0.27 ( TiedRef => \$Registry, Delimiter => q{/} );

my $tzi_key = $Registry->Open(
    'LMachine/SYSTEM/CurrentControlSet/Control/TimeZoneInformation/', {
        Access => Win32::TieRegistry::KEY_READ()
            | Win32::TieRegistry::KEY_WRITE()
    }
);

plan skip_all =>
    'These tests require write access to TimeZoneInformation registry key'
    unless $tzi_key;

my $WindowsTZKey;

{
    foreach my $win_tz_name ( windows_tz_names() ) {
        set_and_test_windows_tz( $win_tz_name, undef, $tzi_key );
    }

    my $denver_time_zone_with_newlines = join( '', "Mountain Standard Time", map { chr } qw(  0 10 0 0 0 0 0 0
        82 0 0 0 63 32 0 0 63 120 0 0 32 0 0 0 72 0 0 0 64 116 122 114 101 115
        46 100 108 108 44 45 49 57 50 0 0 0 0 0 1 0 0 0 63 13 0 0 63 63 63 0 63
        13 0 0 1 0 0 0 64 116 122 114 101 115 46 100 108 108 44 45 49 57 49 0 72
        0 0 0 0 0 0 0 63 120 0 0 213 63 63 0 0 0 0 0 0 ) );

    # We test these explicitly because we want to make sure that at
    # least a few known names do work, rather than just relying on
    # looping through a list.
    for my $pair (
        [ 'Eastern Standard Time',  'America/New_York' ],
        [ 'Dateline Standard Time', '-1200' ],
        [ 'Israel Standard Time',   'Asia/Jerusalem' ],
        [ $denver_time_zone_with_newlines,   'America/Denver' ],
        ) {
        set_and_test_windows_tz( @{$pair}, $tzi_key );
    }
}

done_testing();

sub windows_tz_names {
    $WindowsTZKey = $Registry->Open(
        'LMachine/SOFTWARE/Microsoft/Windows NT/CurrentVersion/Time Zones/',
        { Access => Win32::TieRegistry::KEY_READ() }
    );

    $WindowsTZKey ||= $Registry->Open(
        'LMachine/SOFTWARE/Microsoft/Windows/CurrentVersion/Time Zones/',
        { Access => Win32::TieRegistry::KEY_READ() }
    );

    return unless $WindowsTZKey;

    return $WindowsTZKey->SubKeyNames();
}

sub set_and_test_windows_tz {
    my $windows_tz_name = shift;
    my $olson_name      = shift;
    my $tzi_key         = shift;

    if (   defined $tzi_key
        && defined $tzi_key->{'/TimeZoneKeyName'}
        && $tzi_key->{'/TimeZoneKeyName'} ne '' ) {
        local $tzi_key->{'/TimeZoneKeyName'} = $windows_tz_name;

        test_windows_zone( $windows_tz_name, $olson_name );
    }
    else {
        local $tzi_key->{'/StandardName'} = (
              $WindowsTZKey->{ $windows_tz_name . q{/} }
            ? $WindowsTZKey->{ $windows_tz_name . '/Std' }
            : 'MAKE BELIEVE VALUE'
        );

        test_windows_zone( $windows_tz_name, $olson_name );
    }
}

sub test_windows_zone {
    my $windows_tz_name = shift;
    my $olson_name      = shift;

    my %KnownBad = map { $_ => 1 } ();

    my $tz = DateTime::TimeZone::Local::Win32->FromRegistry();

    ok(
        $tz && DateTime::TimeZone->is_valid_name( $tz->name() ),
        "$windows_tz_name - found valid Olson time zone from Windows"
    );

    if ( defined $olson_name ) {
        my $desc = "$windows_tz_name was mapped to $olson_name";
        if ($tz) {
            is( $tz->name(), $olson_name, $desc );
        }
        else {
            fail($desc);
        }
    }
    else {
    SKIP: {
            if ( !$tz || !DateTime::TimeZone->is_valid_name( $tz->name() ) ) {
                skip(
                    "Time Zone display for $windows_tz_name not testable",
                    1
                );
            }
            my $dt = DateTime->now(
                time_zone => $tz->name(),
            );

            my $olson_offset = int( $dt->strftime("%z") );
            $olson_offset -= 100 if $dt->is_dst();
            my $windows_offset
                = $WindowsTZKey->{"${windows_tz_name}/Display"};

            if ( $windows_offset =~ /^\((?:GMT|UTC)\).*$/ ) {
                $windows_offset = 0;
            }
            else {
                if ( $windows_offset
                    =~ s/^\((?:GMT|UTC)(.*?):(.*?)\).*$/$1$2/ ) {
                    $windows_offset = int($windows_offset);
                }
                else {
                    skip(
                        "Time Zone display for $windows_tz_name not testable",
                        1
                    );
                }
            }

            unless ( $ENV{'MAINTAINER'} ) {
                skip(
                    "$windows_tz_name - Windows offset matches Olson offset (Maintainer only)",
                    1
                );
            }

            if ( $KnownBad{$windows_tz_name} ) {
            TODO: {
                    local $TODO
                        = "Microsoft has some out-of-date time zones relative to Olson";
                    is(
                        $olson_offset, $windows_offset,
                        "$windows_tz_name - Windows offset matches Olson offset"
                    );
                    return;
                }
            }
            elsif ( defined $WindowsTZKey->{"${windows_tz_name}/IsObsolete"}
                && $WindowsTZKey->{"${windows_tz_name}/IsObsolete"} eq
                "0x00000001" ) {
                skip(
                    "$windows_tz_name - deprecated by Microsoft",
                    1
                );
            }
            else {
                is(
                    $olson_offset, $windows_offset,
                    "$windows_tz_name - Windows offset matches Olson offset"
                );
            }
        }
    }
}
