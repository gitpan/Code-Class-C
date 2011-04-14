package Code::Class::C;

use 5.010000;
use strict;
use warnings;

our $VERSION = '0.06';

my $LastClassID = 0;

#-------------------------------------------------------------------------------
sub new
#-------------------------------------------------------------------------------
{
	my ($class, @args) = @_;
	my $self = bless {}, $class;
	return $self->_init();
}

#-------------------------------------------------------------------------------
sub func
#-------------------------------------------------------------------------------
{
	my ($self, $name, $code) = @_;

	my $sign = $self->_parse_signature($name);
	
	die "Error: function name '$sign->{'name'}' is not a valid function name\n"
		if $sign->{'name'} !~ /^[a-z][a-zA-Z0-9\_]*$/;
	die "Error: function must not be named 'main'\n"
		if $sign->{'name'} eq 'main';

	$name = $self->_signature_to_string($sign);
	
	die "Error: trying to redefine function '$name'\n"
		if exists $self->{'functions'}->{$name};

	$self->{'functions'}->{$name} = $self->_load_code_from_file($code);
	
	return $self;
}

#-------------------------------------------------------------------------------
sub attr
#-------------------------------------------------------------------------------
{
	my ($self, $classname, $attrname, $attrtype) = @_;
	die "Error: no class '$classname' defined\n"
		unless exists $self->{'classes'}->{$classname};

	my $class = $self->{'classes'}->{$classname};

	die "Error: attribute name '$attrname' is not a valid attribute name\n"
		if $attrname !~ /^[a-z][a-zA-Z0-9\_]*$/;
	
	$class->{'attr'}->{$attrname} = $attrtype;
	
	return $self;
}

#-------------------------------------------------------------------------------
sub meth
#-------------------------------------------------------------------------------
{
	my ($self, $classname, $name, $code) = @_;
	die "Error: no class '$classname' defined\n"
		unless exists $self->{'classes'}->{$classname};
	
	my $class = $self->{'classes'}->{$classname};
	my $sign = $self->_parse_signature($name);

	die "Error: methodname '$sign->{'name'}' is not a valid method name\n"
		if $sign->{'name'} !~ /^[a-z][a-zA-Z0-9\_]*$/;

	# add implicit "self" first parameter
	unshift @{$sign->{'params'}}, ['self',$classname]; 
	$name = $self->_signature_to_string($sign);

	die "Error: trying to redefine method '$name' in class '$classname'\n"
		if exists $class->{'subs'}->{$name};

	$class->{'subs'}->{$name} = $self->_load_code_from_file($code);
	
	return $self;
}

#-------------------------------------------------------------------------------
sub parent
#-------------------------------------------------------------------------------
{
	my ($self, $classname, @parentclassnames) = @_;
	die "Error: no class '$classname' defined\n"
		unless exists $self->{'classes'}->{$classname};

	my $class = $self->{'classes'}->{$classname};
	
	foreach my $parentclassname (@parentclassnames) {
		push @{$class->{'isa'}}, $parentclassname
			unless scalar grep { $parentclassname eq $_ } @{$class->{'isa'}};
	}
	
	return $self;
}

#-------------------------------------------------------------------------------
sub class
#-------------------------------------------------------------------------------
{
	my ($self, $name, %opts) = @_;
	die "Error: cannot redefine class '$name': $!\n" 
		if exists $self->{'classes'}->{$name};
	die "Error: classname '$name' does not qualify for a valid name\n"
		unless $name =~ /^[A-Z][a-zA-Z0-9\_]*$/;
	die "Error: classname must not be 'Object'\n"
		if $name eq 'Object';
	die "Error: classname must not be longer than 256 characters\n"
		if length $name > 256;
	
	$LastClassID++;
	$self->{'classes'}->{$name} = 
		{
			'id'   => $LastClassID,
			'name' => $name,
			'isa'  => [],
			'attr' => {},
			'subs' => {},
		};

	# define attributes
	my $attr = $opts{'attr'} || {};
	map { $self->attr($name, $_, $attr->{$_}) } keys %{$attr};
	
	# define methods
	my $subs = $opts{'subs'} || {};
	map { $self->meth($name, $_, $subs->{$_}) } keys %{$subs};

	# set parent classes
	$self->parent($name, @{$opts{'isa'} || []});

	return $self;
}

#-------------------------------------------------------------------------------
sub readFile
#-------------------------------------------------------------------------------
{
	my ($self, $filename) = @_;
	open SRCFILE, $filename or die "Error: cannot open source file '$filename': $!\n";
	#print "reading '$filename'\n";
	my $classname = undef;
	my $subname   = undef;
	my $buffer    = undef;
	my $l = 0;
	while (<SRCFILE>) {
		next if /^\/[\/\*]/;
		if (/^\@class/) {
			my ($class, $parents) = 
				$_ =~ /^\@class[\s\t]+([^\s\t\:]+)[\s\t]*\:?[\s\t]*(.*)$/;
			my @parents = split /[\s\t]*\,[\s\t]*/, $parents;

			$self->class($class) unless exists $self->{'classes'}->{$class};
			$self->parent($class, @parents);
			$classname = $class;
		}
		elsif (/^\@attr/) {
			die "Error: no classname present at line $l.\n"
				unless defined $classname;

			my ($attr, $type) =
				$_ =~ /^\@attr[\s\t]+([^\s\t\:]+)[\s\t]*\:?[\s\t]*(.*)$/;
			$type =~ s/[\s\t\n\r]*$//g;

			warn "Warning: attribute definition $classname/$attr overwrites present one.\n"
				if exists $self->{'classes'}->{$classname}->{'attr'}->{$attr};
				
			$self->attr($classname, $attr, $type);
		}
		elsif (/^\@sub/) {
			die "Error: no classname present at line $l.\n"
				unless defined $classname;
			
			#print "($filename:$_)\n";
			if (defined $subname && defined $buffer) {
				# add method to class
				$self->meth($classname, $subname, $buffer);
			}

			($subname) = $_ =~ /^\@sub[\s\t]+(.+)[\s\t\n\r]*$/;
			$buffer = '';
		}
		elsif (defined $classname && defined $subname && defined $buffer) {
			$buffer .= $_;
		}
		$l++;
	}
	if (defined $subname && defined $buffer) {
		# add method to class
		$self->meth($classname, $subname, $buffer);
	}	
	close SRCFILE;
	return 1;
}

#-------------------------------------------------------------------------------
sub toDot
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	die "Error: cannot call toDot() method AFTER generate() method has been called\n"
		if $self->{'autogen'};
	
	my $dot = 
		'digraph {'."\n".
q{
	fontname="Bitstream Vera Sans"
	fontsize=8
 	overlap=scale
	
	node [
		fontname="Bitstream Vera Sans"
		fontsize=8
		shape="record"
	]
	
	edge [
		fontname="Bitstream Vera Sans"
		fontsize=8
		//weight=0.1
	]
	
};

	# add class nodes
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		$dot .= 
			'  '.$classname.' ['."\n".
			'    label="{'.
				$classname.'|'.
				join('\l', map { '+ '.$_.' : '.$class->{'attr'}->{$_} } keys %{$class->{'attr'}}).'\l|'.
				join('\l', map { $_ } keys %{$class->{'subs'}}).'\l}"'."\n".
			"  ]\n\n";
	}
	
	# add class relationships
	$dot .= 'edge [ arrowhead="empty" color="black" ]'."\n\n";
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $parentclassname (@{$class->{'isa'}}) {
			$dot .= '  '.$classname.' -> '.$parentclassname."\n";
		}
	}
	
	# add "contains" relationships
	$dot .= 'edge [ arrowhead="vee" color="gray" ]'."\n\n";
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $attrname (keys %{$class->{'attr'}}) {
			my $attrtype = $class->{'attr'}->{$attrname};
			$dot .= '  '.$classname.' -> '.$attrtype."\n"
				if exists $self->{'classes'}->{$attrtype};
		}
	}
	
	return $dot.'}'."\n";
}

#-------------------------------------------------------------------------------
sub toHtml
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	my $html = '';
	
	$self->_autogen();

	# oben: dropdown mit klassen-namen -> onclick wird klasse unten angezeigt
	# unten: Beschreibung der aktuell ausgewaehlten klasse: isa, attr, subs
	#         (auch geerbte!)
	
	my @classnames = sort keys %{$self->{'classes'}};
	
	return 
		'<html>'.
			'<head>'.
				'<title>API</title>'.
				'<style type="text/css">'.q{
					body {
						background: #fff;
						margin: 0;
						padding: 0;
					}
					body, div, select, h1, h2, h3, p, i, span {
						font-size: 12pt;
						font-family: sans-serif;
						font-weight: 200;
					}
					a {
						color: blue;
					}
						a:hover {
							color: #99f;
						}
					p i {
						font-size: 80%;
					}
					h1 { font-size: 200%; }
					h2 { 
						font-size: 140%;
						padding-bottom: 0.2em;
						border-bottom: solid 1px #ccc;
					}
					h3 { font-size: 120%; }
					#top {
						width: 100%;
						position: fixed;
						top: 0;
						left: 220px;
						background: #eee;
						padding: 1em;
					}
					#left {
						width: 200px;
						float: left;
						background: #eee;
						padding: 1em;
						border-left: solid 1px #666;
						overflow: auto;
					}
					#content {
						padding: 4em 1em 1em 260px;
					}
					select {
						vertical-align: middle;
						padding: 0.3em;
					}
					li {
						font-size: 90%;
						margin: 0 0 0 16px;
						list-style: circle;
					}
						li a {
							text-decoration: none;
						}
					ul {
						margin: 0.2em 0;
						padding: 0;
					}
					dl {
					
					}
						dt {
							margin-top: 0.4em;
						}
						dd {
							margin: 0.6em 0 0 2em;
						}
					.typename {
						color: #66c;
					}
					.typename:hover {
						color: #99f;
					}
					.methname {
						color: green;
					}
					p.methnames {
						border-bottom: dotted 1px #ccc;
						padding-bottom: 10pt;
						margin-bottom: 10pt;
					}
						p.methnames a {
							display: inline-block;
							background: #eee;
							-moz-border-radius: 0.4em;
							-webkit-border-radius: 0.4em;
							border-radius: 0.4em;			
							padding: 4pt 6pt 3pt;
							margin-bottom: 2pt;
						}
					pre {
						background: #eee;
						font-size: 9pt;
						padding: 0.4em 0.5em;
						overflow: auto;
						-moz-border-radius: 0.4em;
						-webkit-border-radius: 0.4em;
						border-radius: 0.4em;
						border: solid 1px #ccc;
						font-weight: 200;
						font-family: Monaco, fixed;
					}
						pre span {
							font-size: inherit;
							font-weight: inherit;
							font-family: inherit;
						}
						pre .keyword {
							color: #099;
						}
						pre .string {
							color: #669;
						}
						pre .comment {
							color: #999;
						}
						pre .call {
							color: #009;
						}
				}.'</style>'.				
				'<script type="text/javascript">'.
					'function showClass (id) {'.
					'  id = \'class-\'+id;'.
					'  document.getElementById(\'content\').innerHTML = document.getElementById(id).innerHTML;'.
					'  scroll(0,0);'.
					'}'.
				'</script>'.
			'</head>'.
			'<body onload="showClass(\''.$classnames[0].'\');">'.
				'<div id="top">'.
					'Class: '.
					'<select onchange="showClass(this.value);">'.
					join('', map {
						'<option value="'.$_.'">'.$_.'</option>'
					} @classnames).
					'</select>'.
				'</div>'.
				'<div id="left">'.
					$self->_mkClassTree().
					'<p><i>generated by Code::Class::C</i></p>'.
				'</div>'.
				'<div id="content"></div>'.
				join('', map {
					'<div id="class-'.$_.'" style="display:none">'.$self->_classToHtml($_).'</div>'
				} @classnames).
			'</body>'.
		'</html>';
		
	sub _mkClassTree
	{
		my ($self) = @_;
		# find top classes (those without any parent classes)
		my @topclasses = ();
		foreach my $classname (sort keys %{$self->{'classes'}}) {
			push @topclasses, $classname
				unless scalar @{$self->{'classes'}->{$classname}->{'isa'}};
		}
		
		my $html = '<ul>';
		foreach my $classname (@topclasses) {
			$html .= 
				'<li>'.
					$self->_mkClassLink($classname).' '.
					$self->_mkSubclassList($classname).
				'</li>';
		}
		return $html.'</ul>';
	}
	
	sub _mkSubclassList
	{
		my ($self, $classname) = @_;
		# find direct children
		my @children = ();
		foreach my $cname (sort keys %{$self->{'classes'}}) {
			foreach my $parentclassname (sort @{$self->{'classes'}->{$cname}->{'isa'}}) {
				push @children, $cname
					if $classname eq $parentclassname;
			}
		}
		return 
			(scalar @children ?
				'<ul>'.
					join('', map { '<li>'.$self->_mkClassLink($_).' '.$self->_mkSubclassList($_).'</li>' } @children).
				'</ul>'
					: '');
	}
		
	sub _classToHtml
	{
		my ($self, $classname) = @_;
		my $class = $self->{'classes'}->{$classname};
		my $html = '<h1 class="typename">'.$classname.'</h1>';
		
		$html .= '<h2>Parent classes</h2><dl><dt>';
		$html .= 
			join(', ', map { $self->_mkClassLink($_) }
				sort @{$class->{'isa'}});
		$html .= '</dt></dl>';
		$html .= '<p><i>none</i></p>' unless scalar @{$class->{'isa'}};

		$html .= '<h2>Child classes</h2><dl><dt>';
		my $subclasses = $self->_get_subclasses();
		$html .= 
			join(', ', map { $self->_mkClassLink($_) }
				sort keys %{$subclasses->{$classname}});
		$html .= '</dt></dl>';
		$html .= '<p><i>none</i></p>' unless scalar keys %{$subclasses->{$classname}};
		
		$html .= '<h2>Attributes</h2><dl>';
		foreach my $attrname (sort keys %{$class->{'attr'}}) {
			$html .= '<dt>'.$self->_mkClassLink($class->{'attr'}->{$attrname}).' '.$attrname.'</dt>';
		}
		$html .= '</dl>';
		$html .= '<p><i>none</i></p>' unless scalar keys %{$class->{'attr'}};
		
		$html .= '<h2>Methods</h2><p class="methnames">';
		my $meths = '';
		foreach my $methname (sort keys %{$class->{'subs'}}) {
			my $sign = $self->_parse_signature($methname);
			my $code = $class->{'subs'}->{$methname};
			   $code =~ s/\t/  /g;
			   $code =~ s/(\r?\n)\s\s/$1/g;
			$html .= '<a href="#'.$sign->{'name'}.'">'.$sign->{'name'}.'</a> ';
			$meths .= 
				'<dt>'.
					'<a name="'.$sign->{'name'}.'"></a>'.
					$self->_mkClassLink($sign->{'returns'}).' : '.
					'<span class="methname">'.$sign->{'name'}.'</span>'.
					' ( '.join(', ', map { $self->_mkClassLink($_->[1]).' '.$_->[0] } @{$sign->{'params'}}).' )'.
				'</dt><dd><pre>'.$self->_highlightC($code).'</pre></dd>';
		}
		$html .= '</p><dl>'.$meths.'</dl>';
		$html .= '<p><i>none</i></p>' unless scalar keys %{$class->{'subs'}};
		
		return $html;
	}
	
	sub _highlightC
	{
		my ($self, $c) = @_;
		$c =~ s/(\"[^\"]*\")/<span class="string">$1<\/span>/g;
		$c =~ s/(if|else|for|return|self|while|void|static)/<span class="keyword">$1<\/span>/g;
		$c =~ s/(\/\/[^\n]*)/<span class="comment">$1<\/span>/g;
		$c =~ s/(\/\*[^\*]*\*\/)/<span class="comment">$1<\/span>/mg;
		$c =~ s/([a-zA-Z\_][a-zA-Z0-9\_]*)\(/<span class="call">$1<\/span>\(/g;
		return $c;
	}

	sub _mkClassLink
	{
		my ($self, $classname) = @_;
		return
			(exists $self->{'classes'}->{$classname} ?
				'<a href="javascript:showClass(\''.$classname.'\');" class="typename">'.
					$classname.
				'</a>'
					: '<span class="typename">'.$classname.'</span>');
	}
}

#-------------------------------------------------------------------------------
sub generate
#-------------------------------------------------------------------------------
{
	my ($self, %opts) = @_;
	
	my $file     = $opts{'file'}    || die "Error: generate() needs a filename.\n";
	my $headers  = $opts{'headers'} || [];
	my $maincode = $self->_load_code_from_file($opts{'main'} || '');
	my $topcode    = $self->_load_code_from_file($opts{'top'} || '');
	my $bottomcode = $self->_load_code_from_file($opts{'bottom'} || '');

	$self->_autogen();
	
	# add standard headers needed
	foreach my $h (qw(string stdio stdlib stdarg)) {
		unshift @{$headers}, $h
			unless scalar grep { $_ eq $h } @{$headers};
	}

	##############################################################################	
	my $ccode = '';
	
	# write headers
	foreach my $hname (@{$headers}) {
		$ccode .= '#include ';
		if ($hname =~ /^(std|string)/) {
			$ccode .= '<'.$hname.'.h>';
		} else {
			$ccode .= '"'.$hname.'.h"';
		}
		$ccode .= "\n";
	}

	$ccode .= q{
/*----------------------------------------------------------------------------*/

#define READ_ARGV \
  Object* argv = (Object*)NULL; \
  int argc = 0; \
  { \
    va_list ap; \
    Object current; \
    if (p != (Object)NULL) { \
      va_start(ap, p); \
      current = p; \
      while (current != (Object)NULL) { \
        argc++; \
        argv = (Object*)realloc(argv, sizeof(Object) * argc); \
        argv[argc-1] = current; \
        current = va_arg(ap, Object); \
      } \
      va_end(ap); \
    } \
  } \

#define DUMP_ARGV \
  { \
    int a; \
    printf("  The method was called with %d parameters:\n", argc); \
    for (a = 0; a < argc; a++) { \
      printf("  [%d] is a %s\n", a, argv[a]->classname); \
    } \
  } \

#define CLEANUP_ARGV \
  free(argv);

/*----------------------------------------------------------------------------*/

typedef struct S_Object* Object;

struct S_Object {
  int classid;
  char classname[256];
  void* data;
};

/*----------------------------------------------------------------------------*/
/* String functions */

void setstr (char* dest, const char* src) {
  int i;
  for (i = 0; i < 256; i++) {
    dest[i] = src[i];
  }
}

int eq (char* s1, char* s2) {
  return (strcmp(s1, s2) == 0);
}

};

	##############################################################################
	# create hash of subclasses for each class
  my %subclasses = %{$self->_get_subclasses()};
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* ISA Function */\n\n";
	$ccode .= 'int isa (int childid, int classid) {'."\n";
	$ccode .= '  if (childid == classid) { return 1; }'."\n";
  my $first = 1;
  foreach my $classname (keys %subclasses) {
    next unless scalar keys %{$subclasses{$classname}};
  	my $classid = $self->{'classes'}->{$classname}->{'id'};
	  my @clauses = ();
    foreach my $childclassname (keys %{$subclasses{$classname}}) {
	  	my $childclassid = $self->{'classes'}->{$childclassname}->{'id'};
	  	push @clauses, 'childid == '.$childclassid.'/*'.$childclassname.'*/';
  	}
		$ccode .=
			'  '.($first ? 'if' : 'else if').' (classid == '.$classid.'/*'.$classname.'*/'.
					 (scalar @clauses ? ' && ('.join(' || ',@clauses).')' : '').') {'."\n".
			'    return 1;'."\n".
			'  }'."\n";
  	$first = 0;
  }
	$ccode .= '  return 0;'."\n";
	$ccode .= '}'."\n\n";

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Types */\n\n";
	my $typedefs = '';
	my $structs  = '';
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};

		# typedef for class-specific struct pointer (member 'data' in S_Object struct)
		$typedefs .= 'typedef struct S_'.$self->_get_c_typename($classname).'* '.$self->_get_c_typename($classname).';'."\n\n";
		
		# struct for the class
		$structs .= 'struct S_'.$self->_get_c_typename($classname).' {'."\n";
		$structs .= '  int dummy'.";\n" unless scalar keys %{$class->{'attr'}};
		foreach my $attrname (sort keys %{$class->{'attr'}}) {
			$structs .= '  '.$self->_get_c_attrtype($class->{'attr'}->{$attrname}).' '.$attrname.";\n";
		}
		$structs .= "};\n\n";
	}
	$ccode .= $typedefs;
	$ccode .= $structs;

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* User top code */\n\n";
	$ccode .= $topcode."\n\n";

	##############################################################################
	$ccode .= $self->_generate_functions()."\n\n";

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* User bottom code */\n\n";
	$ccode .= $bottomcode."\n\n";

	##############################################################################
	if (length $maincode) {
		$ccode .= "/*-----------------------------------------------------------*/\n";
		$ccode .= "/* Main function */\n\n";
		$ccode .= 'int main (int argc, char** argv) {'."\n";
		$ccode .= '  '.$maincode;
		$ccode .= "\n}\n";
	}

	open OUTFILE, '>'.$file
		or die "Error: failed to open output file '$file': $!\n";
	print OUTFILE $ccode;
	close OUTFILE;	
}

################################################################################
################################################################################
################################################################################

#-------------------------------------------------------------------------------
sub _parse_signature
#-------------------------------------------------------------------------------
{
	my ($self, $signature_string) = @_;
	
	# render(self:Square,self:Vertex,self:Point):void
	my $rs = '[\s\t\n\r]*';
	my $rn = '[^\(\)\,\:]+';
	my ($name, $args, $returns) = ($signature_string =~ /^$rs($rn)$rs\($rs(.*)$rs\)$rs\:$rs($rn)$rs$/);
	my @params = map { [split /$rs\:$rs/] } split /$rs\,$rs/, $args;

	my $sign = {
		name    => $name,
		returns => $returns,
		params  => \@params,
	};
	return $sign;
}

#-------------------------------------------------------------------------------
sub _dbg
#-------------------------------------------------------------------------------
{
	my (@msg) = @_;
	eval('use Data::Dump;');
	Data::Dump::dump(\@msg);
}

#-------------------------------------------------------------------------------
sub _get_subclasses
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	my %subclasses = ();
  foreach my $classname (keys %{$self->{'classes'}}) {
  	my $classid = $self->{'classes'}->{$classname}->{'id'};
  	$subclasses{$classname} = {} unless exists $subclasses{$classname};
  	#$subclasses{$classname}->{$classname} = 1;
    foreach my $parentclassname ($self->_get_parent_classes($classname)) {
	  	my $parentclassid = $self->{'classes'}->{$parentclassname}->{'id'};
	  	$subclasses{$parentclassname}->{$classname} = 1;
  	}
	}	
	return \%subclasses;
}

#-------------------------------------------------------------------------------
sub _autogen
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	unless ($self->{'autogen'}) {
		$self->_inherit_members();
		$self->_define_constructors();
		$self->_define_destructors();
		$self->_define_accessors();
		$self->{'autogen'} = 1;
	}
}

#-------------------------------------------------------------------------------
sub _generate_functions
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	
	# find all functions and store them by their name
	my %functions = (); # "<funcname>" => {"<signature>" => [...], ...}
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $name (keys %{$class->{'subs'}}) {
			my $sign = $self->_parse_signature($name);
			$functions{$sign->{'name'}} = {}
				unless exists $functions{$sign->{'name'}};
			
			$functions{$sign->{'name'}}->{$name} = 
				{
					'classname' => $classname,
					'number'    => undef,
					'name'      => $name,
					'code'      => $self->{'classes'}->{$classname}->{'subs'}->{$name},
				};				
		}
	}
	# add normal functions, too
	foreach my $fname (keys %{$self->{'functions'}}) {
		my $sign = $self->_parse_signature($fname);
		$functions{$sign->{'name'}}->{$fname} = 
			{
				'classname' => undef,
				'number'    => undef,
				'name'      => $fname,
				'code'      => $self->{'functions'}->{$fname},
			};		
	}
	# give every implementation a unique number
	foreach my $fname (keys %functions) {
		my $n = 0;
		foreach my $name (keys %{$functions{$fname}}) {
			$functions{$fname}->{$name}->{'number'} = $n;
			$n++;
		}
	}

	######

	# check all overloaded functions: they are only allowed if they
	# take class-typed parameters ONLY!
	my %infos = (); # <functionname> => {...}
	foreach my $fname (keys %functions) {
		#print "($fname)\n";

		# define scheme of signature
		my $first_sign = $self->_parse_signature((keys %{$functions{$fname}})[0]);
		my $returns = 
			(exists $self->{'classes'}->{$first_sign->{'returns'}} ? 
				'Object' : $first_sign->{'returns'});
		my $params = [ # sequence of "Object" or "<c-type>" strings
			map { exists $self->{'classes'}->{$_->[1]} ? 'Object' : $_->[1] }
				@{$first_sign->{'params'}}
		];
		my $all_class_types =
			(scalar(grep { $_ eq 'Object' } @{$params}) == scalar(@{$params}) ? 1 : 0);

		$infos{$fname} = {
			'all-class-types' => $all_class_types,
			'params-scheme' => $params,
			'returns' => $returns,
			'at-least-one-impl-has-zero-params' => 0,
		};

		if (scalar keys %{$functions{$fname}} > 2) {
		
			# check if all signatures match the scheme
			foreach my $name (keys %{$functions{$fname}}) {
				#print "  [$name]\n";
				my $sign = $self->_parse_signature($name);
				   $sign->{'returns'} = 
						(exists $self->{'classes'}->{$sign->{'returns'}} ? 
							'Object' : $sign->{'returns'});
				
				die "Error: overloaded method '$name' does not return a valid ".
				    "return type (is '$sign->{'returns'}', must be '$returns')\n"
				  if $returns ne $sign->{'returns'};

				$infos{$name}->{'at-least-one-impl-has-zero-params'} = 1
					if scalar @{$sign->{'params'}} == 0;

				if ($all_class_types) {
					# all parameters should be class-typed
					map {
						die "Error: overloaded method '$name' is not allowed to take ".
						    "non-class typed parameters\n"
							if !exists $self->{'classes'}->{$_->[1]};					
					}
					@{$sign->{'params'}};
				}
				else {
					# the parameter list should match the $params list
					for (my $p = 0; $p < @{$params}; $p++) {
						my $paramtype  = $params->[$p];
						die "Error: overloaded method '$name' does not ".
						    "follow the scheme 'method(".join(',',@{$params})."):$returns'\n"
							if 
							  ($p > scalar @{$sign->{'params'}} - 1) ||
							  ($paramtype eq 'Object' && 
							   !exists $self->{'classes'}->{$sign->{'params'}->[$p]->[1]}) || 
							  ($paramtype ne 'Object' &&
							   $paramtype ne $sign->{'params'}->[$p]->[1]);
					}
				}
			}
		}
	}
	
	# generate c code
	my $macros   = ''; # macros
	my $protos   = ''; # prototypes for implementation functions
	my $wrappers = ''; # wrapper functions
	my $impls    = ''; # implementation functions
	
	foreach my $fname (sort keys %functions) {
		my $info = $infos{$fname};
	
		my $with_macro = 
			($info->{'all-class-types'} || $info->{'at-least-one-impl-has-zero-params'});
		
		if ($with_macro) {
			# function with only class-typed parameters
		
			# generate a wrapper macro that adds a NULL-pointer to the end of
			# the parameter list (to be able to determine the end of parameter list
			# when analysing them in C)
			$macros .=
				'#define   '.$fname.'(...) __'.$fname.'((Object)NULL,##__VA_ARGS__,(Object)NULL)'."\n".
				'#define __'.$fname.'(null,...) _'.$fname.'(__VA_ARGS__)'."\n\n";
		}

		# generate a wrapper function that analyses the actual parameters
		# and chooses an appropriate implementation and finally calls that impl.
		
		$wrappers .= 
			$info->{'returns'}.' '.
				($with_macro ? '_' : '').$fname.' ('.
				$self->_generate_params_declaration($info).') {'."\n".
			($with_macro ? 
				'  READ_ARGV'."\n".
				''
				#'  printf("[wrapper '.$fname.'(), argc=%d, argv=", argc);'."\n".
				#'  if (argc > 0) {'."\n".
				#'    int i;'."\n".
				#'    for (i = 0; i < argc; i++) {'."\n".
				#'      printf("[%d:%s/%d]", i, argv[i]->classname, argv[i]->classid);'."\n".
				#'    }'."\n".
				#'  }'."\n".
				#'  printf("]\n");'."\n"
				
					: '').
			($info->{'returns'} eq 'void' ? '' : '  '.$info->{'returns'}.' result;'."\n");

		# Note:
		#  - the first pass creates if()-clauses for the exact matches for the parameters
		#  - the second pass creates if()-clauses for isa-based matches for the parameters
		#
		#  => maybe not cool???

		my $first = 1;
		foreach my $name (keys %{$functions{$fname}}) {
			my $impl_c_name = '_impl'.$functions{$fname}->{$name}->{'number'}.'_'.$fname;
			my $c_returns = ($info->{'returns'} eq 'void' ? '' : 'result = ');
			
			$protos .= 
				$info->{'returns'}.' '.$impl_c_name.' ('.
					$self->_generate_params_declaration($info,$name).');'."\n";

			$wrappers .=
				'  '.($first ? 'if' : 'else if').' ('.
					$self->_generate_wrapper_select_clause($info,$name).') { '."\n".
				#'    printf("  [check impl '.$name.']\n");'."\n".
				'    '.$c_returns.$impl_c_name.'('.$self->_generate_params_call($info,$name).');'."\n".
				'  }'."\n";

			#my $class = $self->{'classes'}->{$functions{$fname}->{$name}->{'classname'}};
			$impls .=
				$info->{'returns'}.' '.$impl_c_name.' ('.
					$self->_generate_params_declaration($info,$name).') {'."\n".
				'  '.$functions{$fname}->{$name}->{'code'}."\n".
				'}'."\n\n";

			$first = 0;
		}
		#---- UGLY ---
		# second pass for the isa() select's
		foreach my $name (keys %{$functions{$fname}}) {
			my $impl_c_name = '_impl'.$functions{$fname}->{$name}->{'number'}.'_'.$fname;
			my $c_returns = ($info->{'returns'} eq 'void' ? '' : 'result = ');
			
			$wrappers .=
				'  '.($first ? 'if' : 'else if').' ('.
					$self->_generate_wrapper_select_clause($info,$name,1).') { '."\n".
				#'    printf("  [check impl '.$name.']\n");'."\n".
				'    '.$c_returns.$impl_c_name.'('.$self->_generate_params_call($info,$name).');'."\n".
				'  }'."\n";
		}
		#-------------

		my $p = 0;
		$wrappers .= 
			'  else {'."\n".
			#'    int i = 0;'."\n".
			'    printf("Error: could not find a method implementation for '.
				'\''.$fname.'\' matching the actual parameters\n");'."\n".
			($with_macro ?
				'    DUMP_ARGV'."\n" : '').
			'    exit(1);'."\n".
			($info->{'returns'} eq 'Object' ? '    return (Object)NULL;'."\n" : 
				($info->{'returns'} ne 'void' ? '    return ('.$info->{'returns'}.')0;'."\n" : 
					'')).
			'  }'."\n".
			($with_macro ? 
				'  CLEANUP_ARGV'."\n" : '').
			($info->{'returns'} ne 'void' ? 
				'  return result;'."\n" : '').
			"}\n\n";
	}
	
	return
		"/*-----------------------------------------------------------*/\n".
		"/* Macros for all functions */\n\n".
		$macros."\n".
		
		"/*-----------------------------------------------------------*/\n".
		"/* Prototypes for implementation functions */\n\n".
		$protos."\n".

		"/*-----------------------------------------------------------*/\n".
		"/* Wrapper functions */\n\n".
		$wrappers."\n".

		"/*-----------------------------------------------------------*/\n".
		"/* Implementation functions */\n\n".
		$impls."\n";
}

#-------------------------------------------------------------------------------
sub _generate_wrapper_select_clause
#-------------------------------------------------------------------------------
{
	my ($self, $info, $implname, $use_isa) = @_;
	my $sign = $self->_parse_signature($implname);
	my @clauses = ();
	if ($info->{'all-class-types'}) {
		my $p = 0;
		push @clauses, '(argc == '.scalar(@{$sign->{'params'}}).')';
		foreach my $param (@{$sign->{'params'}}) {
			my $class = $self->{'classes'}->{$param->[1]};
			push @clauses, 
				($use_isa ?
					'isa(argv['.$p.']->classid, '.$class->{'id'}.'/* '.$class->{'name'}.' */)' :
					'(argv['.$p.']->classid == '.$class->{'id'}.'/* '.$class->{'name'}.' */)');
			$p++;
		}
	}
	else {
		my $p = 0;
		foreach my $param (@{$sign->{'params'}}) {
			if (exists $self->{'classes'}->{$param->[1]}) {
				my $class = $self->{'classes'}->{$param->[1]};
				push @clauses, 
					($p == 0 ? 
						'self->classid == '.$class->{'id'} : 
						($use_isa ?
						  'isa(p'.$p.'->classid, '.$class->{'id'}.'/* '.$class->{'name'}.' */)' :
					  	'(p'.$p.'->classid == '.$class->{'id'}.'/* '.$class->{'name'}.' */)')
					 );
			}
			$p++;
		}
	}
	return (scalar @clauses ? join(' && ',@clauses) : '1');	
}

#-------------------------------------------------------------------------------
sub _generate_params_call
#-------------------------------------------------------------------------------
{
	my ($self, $info, $implname) = @_;
	my $sign = $self->_parse_signature($implname);
	my @params = ();
	my $p = 0;
	foreach my $param (@{$sign->{'params'}}) {
		push @params, 
			($info->{'all-class-types'} ? 
				'argv['.$p.']' : 
				($p == 0 ? 'self' : 'p'.$p));
		$p++;
	}
	return join(', ', @params);
}


#-------------------------------------------------------------------------------
sub _generate_params_declaration
#-------------------------------------------------------------------------------
{
	my ($self, $info, $implname) = @_;

	if (defined $implname) {
		my $sign = $self->_parse_signature($implname);
		my @params = ();
		foreach my $param (@{$sign->{'params'}}) {
			my $paramtype = 
				(exists $self->{'classes'}->{$param->[1]} ? 'Object' : $param->[1]);
			#if ($param->[1] eq 'Callback') {
			#	print $param->[1]."\n";
			#	print "  ".(exists $self->{'classes'}->{$param->[1]})."\n";
			#	print "  $paramtype\n";
			#}
			push @params, $paramtype.' '.$param->[0];
		}
		return join(', ', @params);		
	}
	else {
		return 'Object p, ...' if $info->{'all-class-types'};
		
		my @params = ();
		my $p = 0;
		foreach my $param (@{$info->{'params-scheme'}}) {
			push @params, $param.' '.($p == 0 ? 'self' : 'p'.$p);
			$p++;
		}
		return join(', ', @params);	
	}
}

#-------------------------------------------------------------------------------
sub _init
#-------------------------------------------------------------------------------
{
	my ($self, %opts) = @_;

	$self->{'classes'} = {};
	$self->{'functions'} = {};

	# if attributes/methods etc. have been auto-generated
	$self->{'autogen'} = 0;
	
	# prefix for type names created by this module
	$self->{'prefix-types'} = 'T_';
		
	return $self;
}

# inherits all members from parent classes
#-------------------------------------------------------------------------------
sub _inherit_members
#-------------------------------------------------------------------------------
{
	my ($self) = @_;	
	# copy all inherited members from the parent classes
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $parentclassname ($self->_get_parent_classes($classname)) {
			my $parentclass = $self->{'classes'}->{$parentclassname};
			foreach my $membertype (qw(attr subs)) {
				foreach my $membername (keys %{$parentclass->{$membertype}}) {
					if ($membertype eq 'attr' && exists $class->{$membertype}->{$membername}) {
						die "Error: inherited attribute '$membername' in class $classname must be of the same type as in class '$parentclassname'\n"
							if $class->{$membertype}->{$membername} ne $parentclass->{$membertype}->{$membername};
					}
	
					my $orig_membername = $membername;
					if ($membertype eq 'subs') {
						my $sign = $self->_parse_signature($membername);
						$sign->{'params'}->[0]->[1] = $classname;
						$membername = $self->_signature_to_string($sign);
					}
					
					unless (exists $class->{$membertype}->{$membername}) {
						$class->{$membertype}->{$membername} = 
							$parentclass->{$membertype}->{$orig_membername};
					}
				}
			}
		}
	}	
}

#-------------------------------------------------------------------------------
sub _define_constructors
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		
		$self->func(
			'new_'.ucfirst($classname).'():Object',
				
			'  Object obj = (Object)malloc(sizeof(struct S_Object));'."\n".
			'  obj->classid = '.$class->{'id'}.';'."\n".
			'  setstr(obj->classname, "'.$classname.'");'."\n".
			'  obj->data = malloc(sizeof(struct S_'.$self->_get_c_typename($classname).'));'."\n".
			join('',
				map {
					'  (('.$self->_get_c_typename($classname).')(obj->data))->'.$_.' = '.$self->_get_init_c_code($class->{'attr'}->{$_}).';'."\n"
				}
				sort keys %{$class->{'attr'}}
			).
			'  return obj;'."\n"
		);
	}
}

#-------------------------------------------------------------------------------
sub _get_init_c_code
#-------------------------------------------------------------------------------
{
	my ($self, $attrtype) = @_;
	return (exists $self->{'classes'}->{$attrtype} ? '(Object)NULL' : '('.$attrtype.')0');
}

#-------------------------------------------------------------------------------
sub _define_destructors
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		
		$self->func(
			'delete(obj:'.$classname.'):void',
				
			'free(('.$self->_get_c_typename($classname).')(obj->data));'."\n".
			'free(obj);'."\n"
		);
	}
}

#-------------------------------------------------------------------------------
sub _define_accessors
#-------------------------------------------------------------------------------
{
	my ($self) = @_;
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $attrname (keys %{$class->{'attr'}}) {
			#my $attrtype = $self->_get_c_attrtype($class->{'attr'}->{$attrname});
			my $attrtype = $class->{'attr'}->{$attrname};

			# getter
			$self->meth(
				$classname,
				'get'.ucfirst($attrname).'():'.$attrtype,
				'return (('.$self->_get_c_typename($classname).')(self->data))->'.$attrname.';',
			);

			# getter to pointer
			$self->meth(
				$classname,
				'get'.ucfirst($attrname).'Ptr():'.
					(exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype).'*',
				
				'return &((('.$self->_get_c_typename($classname).')(self->data))->'.$attrname.');',
			);

			# setter
			$self->meth(
				$classname,
				'set'.ucfirst($attrname).'(value:'.$attrtype.'):void',
				'(('.$self->_get_c_typename($classname).')(self->data))->'.$attrname.' = value;',
			);
			
			# setter for pointer
			$self->meth(
				$classname,
				'set'.ucfirst($attrname).'Ptr(value:'.
					(exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype).'*):void',
					
				'if (value == NULL) { printf("In set'.ucfirst($attrname).'Ptr(): cannot handle NULL pointer\n"); exit(1); }'.
				'(('.$self->_get_c_typename($classname).')(self->data))->'.$attrname.' = *value;',
			);			
		}
	}
}

#-------------------------------------------------------------------------------
sub _get_c_typename
#-------------------------------------------------------------------------------
{
	my ($self, $type) = @_;
	return (exists $self->{'classes'}->{$type} ? $self->{'prefix-types'}.$type : $type);
}

#-------------------------------------------------------------------------------
sub _get_c_attrtype
#-------------------------------------------------------------------------------
{
	my ($self, $attrtype) = @_;
	return (exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype);
}

#-------------------------------------------------------------------------------
sub _signature_to_string
#-------------------------------------------------------------------------------
{
	my ($self, $sign) = @_;
	return
		$sign->{'name'}.
		'('.join(',',map { $_->[0].':'.$_->[1] } @{$sign->{'params'}}).'):'.
		$sign->{'returns'};
}

#-------------------------------------------------------------------------------
sub _load_code_from_file
#-------------------------------------------------------------------------------
{
	my ($self, $code) = @_;
	$code = '' unless defined $code;
	if (($code =~ /^\.?\.?\/[^\*]/) || ($code !~ /\n/ && -f $code && -r $code)) {
		open SRCFILE, $code or die "Error: cannot open source file '$code': $!\n";
		#print "reading '$code'\n";
		$code = join '', <SRCFILE>;
		close SRCFILE;
	}
	$code =~ s/^[\s\t\n\r]*//g;
	$code =~ s/[\s\t\n\r]*$//g;
	$code =~ s/(\r?\n\r?)([^\s])/$1  $2/g;
	return $code;
}

#-------------------------------------------------------------------------------
sub _get_parent_classes
#-------------------------------------------------------------------------------
{
	my ($self, $classname) = @_;
	my @parents = ();
	my @parents_parents = ();
	my $class = $self->{'classes'}->{$classname};
	foreach my $name (@{$class->{'isa'}}) {
		push @parents, $name;
		push @parents_parents, $self->_get_parent_classes($name);
	}
	push @parents, @parents_parents;
	# delete dublicates
	my @clean = ();
	map {
		my $x = $_;
		push(@clean, $x) unless scalar(grep { $x eq $_ } @clean);
	} 
	@parents;
	return @clean;
}

#-------------------------------------------------------------------------------
1;
__END__

=head1 NAME

Code::Class::C - Perl extension for creating ANSI C code from a set
of class definitions to accomplish an object-oriented programming style.

=head1 SYNOPSIS

  use Code::Class::C;
  my $gen = Code::Class::C->new();
  
  $gen->class('Shape',
    subs => {
      'getLargest(s:Shape):Shape' => 'c/Shape.getLargest.c',
      'calcArea():float' => q{
        return 0.0;
      },
    },
  );
  
  $gen->class('Circle',
    isa => ['Shape'],
    attr => {
      'radius' => 'float',
    },
    subs => {
      'calcArea():float' => q{
        return 3.1415 * getRadius(self) * getRadius(self);
      },
    },
  );

=head1 DESCRIPTION

This module lets you define a set of classes (consisting of
attributes and methods) and then convert these definitions
to ANSI C code. The module creates all the object oriented 
abstractions so that the application logic can be programmed
in an object oriented fashion (create instances of classes,
access attributes, destroy instances, method dispatch etc.).

=head2 Constructor

=head3 new()

  my $gen = Code::Class::C->new();
  
The constructor of Code::Class::C takes no arguments and returns
a new generator instance with the following methods.

=head2 Methods

=head3 class( I<name>, I<options> )

The class() method lets you define a new class:

  $gen->class('Circle',
    isa => ['Shape'],
    attr => {
      'radius' => 'float',
    },
    subs => {
      'calcArea():float' => q{
        return 3.1415 * getRadius(self) * getRadius(self);
      },
    },
  );

The class() method takes as first argument the name of the class.
The name has to start with a capitol letter and may be followed
by an arbitrary amount of letters, numbers or underscore (to be
compatible with the ANSI C standard).

The special class name I<Object> is not allowed as a classname.
A classname must not be longer than 256 characters.

After the first argument the optional parameters follow
in any order:

=head4 isa => I<Arrayref of classnames>

The C<isa> option lets you specify zero or more parent classes of the class
that is to be defined.

=head4 attr => I<Hashref of attributes>

The C<attr> option lets you define the attributes of the class that
is to be defined. 

The hash key is the name of the attribute
(starting with a small letter and followed by zero or more
letters, numbers or underscore; note: attribute names are case-insensitive).

The hash value is the C-type of the attribute.
Here you can use basic C types OR class names (because each class becomes
available as a native C type when the C code is generated).

=head4 subs => I<Hashref of methods>

The C<subs> option lets you define the methods of the class that is to
be defined.

The hash key is the signature of the method, e.g.

  calcArea(float x, MyClass y):int

The hash value is the C sourcecode of the method (s.b. for details).
The hash value can optionally be a filename. In this case, the file's
content is used as the method's body.

=head3 attr( I<classname>, I<attribute-name>, I<attribute-type> )

Defines an attribute in a class with the given name and type.

  $gen->attr('Shape','width','float');

=head3 meth( I<classname>, I<method-signature>, I<c-code> )

Defines a method in a class of the given signature using the
given piece of C code (or filename).

  $gen->meth('Shape','calcArea():float','...');

=head3 parent( I<classname>, I<parent-classname>, ... )

Defines the parent class(es) of a given class.

  $gen->parent('Shape','BaseClass1','BaseClass2');

=head3 readFile( I<filename> )

readFile() takes one argument, a filename, loads this file and extracts
class, attribute and method definitions from it.

  $gen->readFile('c/Triangle.c');

Here is an example file:

  //------------------------------------------------------------------------------
  @class Triangle: Shape, Rectangle
  
  //------------------------------------------------------------------------------
  @attr prop:int
  
  //------------------------------------------------------------------------------
  // calculates the area of the triangle
  //
  @sub calcArea():float
  
  return self->width * self->height;
  
  //------------------------------------------------------------------------------
  // calculates the length of the outline of the triangle
  //
  @sub calcOutline():float
  
  return getWidth(self) * 2 + getHeight(self) * 2;

A line starting with '//' is ignored.
A line that starts with an '@' is treated as a class or
attribute definition line or as the start of a method definition.
I hope this is self-explanatory?

Such files can be saved with an ".c" extension so that you can open
them in your favourite C code editor and have fun with the highlighting.

=head3 func( I<signature>, I<c-code-or-filename> )

The func() method defines a normal C function.
It takes as parameters the signature of the function and the code
(which can be a code string or a filename):

  $gen->func('doth(float f, Shape s):int', '/* do sth... */');

=head3 generate( I<options> )

  $gen->generate(
    file    => './main.c',
    headers => ['stdio','opengl'],
    main    => 'c/main.c',
    top     => 'c/top.c',
    bottom  => 'c/bottom.c',
  );

The generate() method generates a single ANSI C compliant source file
out of the given class definitions.

The options are:

=head4 file => I<filename>

This defines the name of the C output file.
This option is mandatory.

=head4 headers => I<Arrayref of headernames>

This defines C headers that are to be included in the generated C file.

=head4 main => I<Source or filename of main function body>

This defines the body (C code) of the main function of the generated
C file. This can be either C code given as a string OR a filename
which is loaded.

=head4 top => I<Source or filename of C code>

This method adds arbitrary C code to the generated C file. The code
is added after the class structs/typedefs and before the method (function)
declarations.

=head4 bottom => I<Source or filename of C code>

This method adds arbitrary C code to the generated C file. The code
is added to the end of the file, but before the main function.

=head3 toDot()

This method generates a Graphviz *.dot string out of the class hierarchy
and additional information (attributes, methods). The dot string is
returned.

=head3 toHtml()

This method creates a HTML API documentation to the class hierarchy that
is defined. The HTML string is returned.

=head2 Object oriented features & C programming style

Throughout this document the style of programming that module lets the
programmer use, is called I<object oriented>, but this is just the canonical
name, actually it is I<class oriented> programming.

So you have defined a bunch of classes with attributes and methods.
But how do you program the method logic in C? This module promises
to make it possible to do this in an object-oriented fashion,
so this is the section where this fashion is described.

For a more complete example, see the t/ directory in the module
dictribution.

=head3 Class definition

This module lets you define classes and their methods and attributes.
Class definition is not possible from within the C code.

=head3 Instanciation

Arbitrary instances of classes can be created from within the C code.

Suppose you defined a class named 'Circle'. You can then create an
instance of that class like so (C code):

  Object c = new_Circle();

Important: B<All class instances in C are of the type "Object">!

=head3 Instance destruction

Since there is a way to create instances, there is also a way to
destroy them (free the memory they occupy).

A generic C function delete() is generated which can be used to
destruct any object/instance:

  Object c = new_Circle();
  delete(c); // c now points to NULL

=head3 Inheritance

A class inherits all attributes and methods from its parent class or classes.
So multiple inheritance (multiple parent classes) is allowed.

=head3 Attribute access

Suppose you defined a class named 'Circle' with an attribute
(could also be inherited). Then you can access this attribute
the following:

  float r;
  float* r_ptr;
  int x = 42.0;
  Object c = new_Circle();
  r = getRadius(c);
  r_ptr = getRadiusPtr(c);
  
  setRadius(c, x);
  setRadiusPtr(c, &x);

As you can see, all methods (either getter or setter or other ones)
need to get the object/instance as first parameter.
B<This "self" parameter need not be written when defining the method>,
remember to define a method, only the B<addtional> parameters
are to be written:

  calcArea(int param):float

Remember: B<Always access the instance/object attributes via the
getter or setter methods!>.

=head3 Attribute overloading

Attributes once defined, must not be re-defined by child classes.

=head3 Method invocation

To invoke a method on an object/instance:

  Object c = new_Circle();
  printf("area = %f\n", calcArea(c));

The first argument of the method call is the object/instance the
method is invoked on.

=head3 Method overloading

Methods once defined, can be overloaded by methods of the same class.
Methods in a class can also be re-defined by child classes.

If a child class overwrites the method of one of its parent classes,
the signatures must be the same, B<regarding the non-class typed parameters>.

To illustrate this, here is an example of a parent class method
signature: C<doSth(Shape s, float f):void> - the first parameter is an object
of class 'Shape', the second a native C float.

Suppose another classes tries to overwrite this method. In this case the
first parameter's type is allowed to change (to any other class type!),
but the second not, because its a native type. This will work:
C<doSth(Circle s, float f):void> but this not: C<doSth(int s, float f):void>

=head3 Access "self" from within methods

When writing methods you need access to the object instance.
This variable is "magically" available and is named "self".
Here is an example of a method body:

  printf("radius of instance is %f\n", getRadius(self));

=head3 Default attributes

The following attributes are present in all classes. These attributes
differ compared to user-defined attributes in the way that they can
be accessed directly by dereferencing the instance/object pointer:

=head4 I<int> classid

Each class has a globally unique ID, a positive number greater than zero.

  Object c = new_Circle();
  printf("c.classid = %d\n", c->classid);

=head4 I<char*> classname

This is the name of the class of the object/instance.
To access the classname, use accessor methods like for all
other attributes, e.g.:

  Object c = new_Circle();
  printf("c.classname = %s\n", c->classname);

Beware, that, when you change the classname at runtime, methods may not be able
to determine the actual implementation of a method to be applied to an
object/instance.

=head2 LIMITATIONS & BUGS

This module is an early stage of development and has therefor some
limitations and bugs. If you think, this module needs a certain feature,
I would be glad to hear from you, also, if you find a bug, I would be
glad to hear from you.

=head2 EXPORT

None by default.

=head1 SEE ALSO

Please send any hints on other modules trying to accomplish the same
or a similar thing. I haven't found one, yet.

=head1 AUTHOR

Tom Kirchner, E<lt>tom@tomkirchner.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Tom Kirchner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
