/// Builders for the JSON schemas the AI answers in. Structured outputs need
/// every property required and no extra properties, so unknown values come
/// back as '' or [] rather than missing.
///
/// A minimal copy of Udyoga's builders (lib/domain/schema.dart there), kept
/// private to the package.
library;

import 'json.dart';

Json object(Map<String, Json> properties, {String? description}) => {
  'type': 'object',
  'description': ?description,
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};

Json array(Json items, {String? description}) => {
  'type': 'array',
  'description': ?description,
  'items': items,
};

Json string([String? description]) => {'type': 'string', 'description': ?description};

Json integer([String? description]) => {'type': 'integer', 'description': ?description};

Json boolean([String? description]) => {'type': 'boolean', 'description': ?description};

Json oneOf(List<String> values, [String? description]) => {
  'type': 'string',
  'enum': values,
  'description': ?description,
};
