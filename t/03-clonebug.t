#
#===============================================================================
#
#         FILE:  03-clonebug.t
#
#  DESCRIPTION:  Test for clone bug missing
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pavel Boldin (), <davinchi@cpan.org>
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  13.08.2009 02:24:32 MSD
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Clone qw/clone/;

use Test::More tests => 2;                      # last test to print

my $m = 'SQL::Filter';

use_ok( $m );

my $filter = [
    {
        field	=> 'test',
        on_true => {
            where => {
                name => '$testme',
            },
        },
    }
];

my $filter_clone = clone( $filter );

my $input = {
    test => 1,
    testme => 'there there',
};


my $f = $m->new(
    filter => $filter,
    input => $input,
    tables => [],
    fields => []
);


is_deeply( $filter, $filter_clone );
