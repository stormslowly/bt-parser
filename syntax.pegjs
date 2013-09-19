{
	function def(type, init, proto) {
		function Class() {
			var instance = Object.create(Class.prototype),
				args = Array.prototype.slice.call(arguments),
				init = instance.__init__;

			switch (typeof init) {
				case 'function':
					init.apply(instance, args);
					break;

				case 'string':
					instance[init] = args;
					break;

				default:
					init.forEach(function (key, i) {
						if (args[i] !== undefined) {
							instance[key] = args[i];
						}
					});
					break;
			}

			return instance;
		}

		Class.prototype = proto || {};
		Class.prototype.type = type;
		Class.prototype.constructor = Class;
		Object.defineProperty(Class.prototype, '__init__', {value: init});
		Class.prototype.at = function (start, end) {
			this.loc = {start: start, end: end};
			return this;
		};
		Class.prototype.toString = function () { return '[' + this.type + ']' };
		Class.prototype.toJSON = function () {
			var tmp = {};
			for (var key in this) {
				tmp[key] = this[key];
			}
			return tmp;
		};

		return Class;
	}

	var program = def('Program', 'body');
	var id = def('Identifier', ['name']);
	var member = def('MemberExpression', ['object', 'property', 'computed']);
	var literal = def('Literal', ['value']);
	var obj = def('ObjectExpression', function () {
		this.properties = Array.prototype.map.call(arguments, function (property) {
			property.type = 'Property';
			return property /* key, value */;
		});
	});
	var assign = def('AssignmentExpression', ['left', 'right', 'operator'], {operator: '='});
	var update = def('UpdateExpression', ['argument', 'operator', 'prefix']);
	var call = def('CallExpression', ['callee', 'arguments'], {arguments: []});
	var create = def('NewExpression', ['callee', 'arguments'], {arguments: []});
	var vars = def('VariableDeclaration', function () {
		this.declarations = Array.prototype.map.call(arguments, function (declaration) {
			declaration.type = 'VariableDeclarator';
			return declaration /* id, init */;
		});
	}, {kind: 'var'});
	var inContext = def('WithStatement', ['object', 'body']);
	var stmt = def('ExpressionStatement', ['expression']);
	var block = def('BlockStatement', 'body');
	var ret = def('ReturnStatement', ['argument']);
	var func = def('FunctionExpression', ['params', 'body']);
	var array = def('ArrayExpression', 'elements');
	var binary = def('BinaryExpression', ['left', 'operator', 'right']);
	var unary = def('UnaryExpression', ['operator', 'argument'], {prefix: true});
}

start = block:block {
	return program(
		vars({id: id('$RESULT'), init: obj()}),
		inContext(id('$RESULT'), block)
	);
}

pos = { return {line: line(), column: column() - 1} }

space_char = [ \t\n\r]
_ = space_char*
__ = space_char+
eol = ";" _

hex_digit = [0-9A-F]i

hex_number = "0x" number:$(hex_digit+) { return parseInt(number, 16) }
oct_number = "0" number:$([0-7]+) { return parseInt(number, 8) }
bin_number = "0b" number:$([01]+) { return parseInt(number, 2) }
dec_number = number:$([0-9]+) { return parseInt(number, 10) }

number = number:(hex_number / bin_number / oct_number / dec_number) _ { return literal(number) }

char
  // In the original JSON grammar: "any-Unicode-character-except-"-or-\-or-control-character"
  = [^"\\\0-\x1F\x7f]
  / '\\"'  { return '"';  }
  / "\\\\" { return "\\"; }
  / "\\/"  { return "/";  }
  / "\\b"  { return "\b"; }
  / "\\f"  { return "\f"; }
  / "\\n"  { return "\n"; }
  / "\\r"  { return "\r"; }
  / "\\t"  { return "\t"; }
  / "\\u" digits:$(hex_digit hex_digit hex_digit hex_digit) {
	  return String.fromCharCode(parseInt(digits, 16));
	}

string = '"' chars:$(char*) '"' _ { return literal(chars) }

name = name:$([A-Za-z_] [A-Za-z_0-9]*) _ { return id(name) }
indexed = name:name index:("[" expr:expression? "]" _ { return expr }) { return member(name, index, true) }
ref = indexed / name

op_unary = op:[!~+-] _ { return op }
op_binary = op:($([<>=!] "=") / "<<" / ">>" / "||" / "&&" / [<>%|^&*/+-]) _ { return op }
op_assign = op:$(("<<" / ">>" / [%|^&*/+-])? "=") _ { return op }
op_update = op:("++" / "--") _ { return op }

update_before = op:op_update ref:ref { return update(ref, op, true) }
update_after = ref:ref op:op_update { return update(ref, op) }
update = update_before / update_after

assignment = update / ref:ref op:op_assign _ expr:expression { return assign(ref, expr, op) }

struct = type:("struct" / "union") __ name:name? bblock:bblock {
	if (type === 'union') {
		var newBody = [
			vars({
				id: id('$START'),
				init: call(member(id('$BINARY'), id('tell')))
			})
		];

		var seekBack = stmt(call(
			member(id('$BINARY'), id('seek')),
			[id('$START')]
		));

		bblock.body.forEach(function (stmt, index) {
			if (index > 0) newBody.push(seekBack);
			newBody.push(stmt);
		});

		bblock.body = newBody;
	}

	bblock = block(
		vars({id: id('$RESULT'), init: obj()}),
		inContext(id('$RESULT'), bblock),
		ret(id('$RESULT'))
	);

	var expr = call(member(id('jBinary'), id('Type')), [
		obj({
			key: id('read'),
			value: func([], bblock)
		})
	]);

	if (name) {
		expr = assign(member(member(id('$BINARY'), id('typeSet')), name), expr);
	}

	return expr;
}

type = struct / prefix:(prefix:"unsigned" __ { return prefix + ' ' })? name:name { return literal(prefix + name.name) }

single_expression = "(" expr:expression ")" _ { return expr }
                  / op:op_unary expr:single_expression { return unary(op, expr) }
                  / assignment / call / ref / string / number

expression = left:single_expression op:op_binary right:expression { return binary(left, op, right) }
           / single_expression

args = args:(ref:ref "," _ { return ref })* last:ref? {
	if (last) args.push(last);
	return args;
}

call = ref:ref "(" _ args:args ")" _ {
	args.unshift(id('$BINARY'));
	return call(member(ref, id('call')), args);
}

var_file = type:type ref:ref {
	return stmt(assign(
		member(id('$RESULT'), ref instanceof member ? ref.object : ref),
		call(
			member(id('$BINARY'), id('read')),
			[ref instanceof member ? array(literal('array'), type, ref.property || id('undefined')) : type]
		)
	));
}

var_local = ("local" / "const") __ type:type ref:(assignment / ref) {
	return vars(
		ref instanceof assign
			? {id: ref.left instanceof member ? ref.left.object : ref.left, init: ref.right}
			: ref instanceof member
				? {id: ref.object, init: ref.property ? create(id('Array'), [ref.property]) : array()}
				: {id: ref}
	);
}

var = var_local / var_file

statement = stmt:(var / expr:(struct / expression) { return stmt(expr) }) eol {
	return stmt;
}

block = stmts:statement* {
	return block.apply(null, stmts);
}

bblock = "{" _ block:block "}" _ { return block }