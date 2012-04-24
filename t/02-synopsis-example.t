

use strict;
use warnings;

use Test::More tests => 2;

use SQL::Filter;
my $filter = SQL::Filter->new(
    table => 'testme t',
    field => '*',
    filter => [ # or subclass and return them from get_filter method
	{
	    tables  => [ [ 'another_test a' ] ], # natural join that
	    field  => 'field',
	    on_true => {
		where => {
		    'a.field' => { -like => '$field' },
		},
	    },
	},
	{
	    field => 'another_field',
	    cond   => {
		first_value => {
		    where => {
			'a.first_column' => { -not_like => 'first_value' },
		    },
		},
	    },
	},
    ],
    input => {
	field => 'value',
	another_field => 'first_value',
    },
);

my ($stmt, @bind) = $filter->select;

is( $stmt, 'SELECT * FROM testme t NATURAL LEFT JOIN another_test a WHERE ( ( a.field LIKE ? AND a.first_column NOT LIKE ? ) )', 'statement');
is_deeply( \@bind, [ qw/%value% first_value/ ], 'bind' );
