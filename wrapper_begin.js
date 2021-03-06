function LittleEndian() {}
function ReadByte() {}

var $BINARY = new jBinary(1024, {
	uint: 'uint32'
});

function JB_UNION(binary) {
	this.binary = binary;
	this.begin = this.end = binary.tell();
}

JB_UNION.prototype.read = function () {
	var result = this.binary.read.apply(this.binary, arguments);
	this.end = Math.max(this.end, this.binary.tell());
	this.binary.seek(this.begin);
	return result;
};

JB_UNION.prototype.done = function () {
	this.binary.seek(this.end);
};

function JB_ENUM(obj) {
	var prev = -1;
	for (var key in obj) {
		var value = obj[key];
		if (value === undefined) {
			value = obj[key] = prev + 1;
		}
		prev = value;
	}
	return obj;
}

function JB_DECLARE(oldValue, newValue) {
	if (oldValue === undefined) {
		return newValue;
	} else {
		if (oldValue !== null && oldValue.jb_isMultiple) {
			oldValue.push(newValue);
		} else {
			oldValue = [oldValue, newValue];
			oldValue.jb_isMultiple = true;
			oldValue.valueOf = function () {
				return this[this.length - 1];
			};
		}
		return oldValue;
	}
}

function JB_VALUEOF(value) {
	return typeof value === 'object' && value !== null ? value.valueOf() : value;
}

function JB_ASSIGN_MEMBER(obj, prop, value) {
	if (typeof obj === 'string') {
		obj = obj.slice(0, prop) + value + obj.slice(prop + 1);
	} else {
		obj[prop] = value;
	}
	return obj;
}

$TYPESET = $BINARY.typeSet;