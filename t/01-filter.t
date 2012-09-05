#
#===============================================================================
#
#         FILE:  01-filter.t
#
#  DESCRIPTION:  test filter
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pavel Boldin (), <davinchi@cpan.org>
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  03.08.2009 22:48:54 MSD
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More;

use Data::Dumper;
use YAML::Syck;

my $tests = Load( do { local $/; <DATA> } );

plan tests => scalar @$tests + 1;

use_ok('SQL::Filter');

foreach my $test (@$tests) {
    my $filter = SQL::Filter->new(
        table => 'testme',
        field => '*',
        input => $test->{input},
        filter => $test->{filter}
    );

    is_deeply( [ $filter->select ], $test->{sql}, $test->{name} );
}

__DATA__
---
- filter: &1
    - cond:
        therethere:
          field: search_str_test
          tables:
            -
              - table t1
          where:
            search_str_test:
              -like: $search_str_test
      field: search_str
      on_false:
        tables:
          -
            - table t
      on_true:
        where:
          sd.search_str:
            -like: $search_str
      tables:
        -
          - LEFT OUTER JOIN service_details s_d ON s_d.service_id = service_id
  input:
    search_str: thousand of them
    search_str_test: 10
  sql:
    - 'SELECT * FROM testme LEFT OUTER JOIN service_details s_d ON s_d.service_id = service_id WHERE ( sd.search_str LIKE ? )'
    - %thousand of them%
  name: simple join and -like
- filter: *1
  input:
    search_str: therethere
    search_str_test: '%string%'
  sql:
    - 'SELECT * FROM testme LEFT OUTER JOIN service_details s_d ON s_d.service_id = service_id NATURAL LEFT JOIN table t1 WHERE ( search_str_test LIKE ? )'
    - '%string%'
  name: condition and joins
- filter: *1
  input:
    search_str:
    search_str_test: '%string%'
  sql:
    - 'SELECT * FROM testme LEFT OUTER JOIN service_details s_d ON s_d.service_id = service_id NATURAL LEFT JOIN table t'
  name: on_false
- filter: &2
    - cond:
        given:
          where:
            s.user2_id:
              - -and
              - !!perl/ref
                =:
                  - '!= 0'
              - '!=': $user_id
        none:
          where:
            s.user2_id: !!perl/ref
              =:
                - = 0
        recieved:
          where:
            s.user2_id:
              - -and
              - !!perl/ref
                =:
                  - '!= 0'
              - =: $user_id
      field: partial_control
  input:
    partial_control: given
    user_id: 98
  sql:
    - 'SELECT * FROM testme  WHERE ( ( s.user2_id != 0 AND s.user2_id != ? ) )'
    - 98
  name: condition check
- filter: *2
  input:
    partial_control: recieved
    user_id: 98
  sql:
    - 'SELECT * FROM testme  WHERE ( ( s.user2_id != 0 AND s.user2_id = ? ) )'
    - 98
  name: another condition check
- filter: *2
  input:
    partial_control: none
  sql:
    - SELECT * FROM testme  WHERE ( s.user2_id = 0 )
  name: third condition
