package Redis::OpenTracing;

use strict;
use warnings;

use syntax 'maybe';

our $VERSION = 'v0.2.3';

use Moo;
use Types::Standard qw/HashRef Maybe Object Str Value is_Str/;

use OpenTracing::GlobalTracer;
use Scalar::Util 'blessed';



has 'redis' => (
    is => 'ro',
    isa => Object, # beyond current scope to detect if it is a Redis like client
    required => 1,
);



has '_redis_client_class_name' => (
    is => 'lazy',
    isa => Str,
);

sub _build__redis_client_class_name {
    blessed( shift->redis )
};



sub _operation_name {
    my ( $self, $method_name ) = @_;
    
    return $self->_redis_client_class_name . '::' . $method_name;
}



has 'tags' => (
    is => 'ro',
    isa => HashRef[Value],
    default => sub { {} }, # an empty HashRef
);



our $AUTOLOAD; # keep 'use strict' happy

sub AUTOLOAD {
    my ($self) = @_;
    
    my $method_call    = do { $_ = $AUTOLOAD; s/.*:://; $_ };
    my $component_name = $self->_redis_client_class_name( );
    my $db_statement   = uc($method_call);
    my $operation_name = $self->_operation_name( $method_call );
    
    my $method_wrap = sub {
        my $self = shift;
        my $scope = _global_tracer_start_active_span(
            $operation_name,
            tags => {
                'component'     => $component_name,
                
                %{ $self->tags( ) },
                
                'db.statement'  => $db_statement,
                'db.type'       => 'redis',
                'span.kind'     => 'client',
                
            },
        );
        
        $scope->close();
        
        return $self->redis->$method_call(@_);
    };
    
    # Save this method for future calls
    no strict 'refs';
    *$AUTOLOAD = $method_wrap;
    
    goto $method_wrap;
}



sub _global_tracer_start_active_span {
    my $operation_name = shift;
    my @args = @_;
    
    return OpenTracing::GlobalTracer->get_global_tracer()->start_active_span(
        $operation_name,
        @args,
    );
}



sub DESTROY { } # we don't want this to be dispatched



1;
