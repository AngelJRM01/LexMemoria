"""Shared validation for privately authored, structured exercises."""
import re


def validate_exercise(data):
    kind = data['type']
    options = data.get('options', [])
    correct = data.get('correct')
    if kind not in ('qa', 'cloze', 'truefalse', 'order', 'case', 'test'):
        raise ValueError('Tipo de ejercicio desconocido')
    if kind == 'cloze' and not re.search(r'\{\{c[1-9]\d*::[^{}]+\}\}', data['front']):
        raise ValueError('Añade un hueco válido: {{c1::respuesta}}')
    if kind in ('test', 'truefalse') or (kind == 'case' and options):
        if not 2 <= len(options) <= 6 or correct is None or not 0 <= correct < len(options):
            raise ValueError('Opciones o solución no válidas')
    if kind == 'truefalse' and options != ['Verdadero', 'Falso']:
        raise ValueError('Verdadero/falso requiere las dos opciones estándar')
    if kind == 'order' and not 2 <= len(options) <= 12:
        raise ValueError('Añade entre 2 y 12 elementos en el orden correcto')
    if any(not isinstance(v, str) or not v.strip() or len(v) > 2000 for v in options):
        raise ValueError('Opciones vacías o demasiado largas')
    if len(set(options)) != len(options):
        raise ValueError('Las opciones deben ser distintas')


def grade_exercise(data, response):
    if response is None:
        return None
    options = data.get('options', [])
    if data['type'] == 'order':
        if not isinstance(response, list) or len(response) != len(options) or set(response) != set(range(len(options))):
            raise ValueError('La respuesta debe ordenar todos los elementos sin duplicados')
        return response == list(range(len(options)))
    if data['type'] in ('test', 'truefalse', 'case') and options:
        if type(response) is not int or not 0 <= response < len(options):
            raise ValueError('Respuesta fuera de las opciones')
        return response == data.get('correct')
    raise ValueError('El ejercicio no admite respuesta estructurada')
