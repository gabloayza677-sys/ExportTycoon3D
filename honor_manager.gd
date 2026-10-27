extends Node
# ============================================================
# honor_manager.gd   ->  res://honor_manager.gd
# Autoload con el nombre exacto: HonorManager
# YA NO hay barra de honor visible: es una puntuación oculta
# ("Consecuencias") que solo se revela en la evaluación final.
# ============================================================

signal honor_cambiado(puntos: int, cambio: int)
signal consecuencia(texto: String, cambio: int)

const HONOR_INICIAL: int = 100

# Calibración de la eficiencia (segundos). Ajusta a tu ritmo de juego.
const SEG_IDEAL_CAJA: float = 8.0     # entregar una caja cada 8 s = 100 %
const SEG_MALO_CAJA: float = 35.0     # 35 s o más por caja = 0 %
const SEG_IDEAL_PALET: float = 40.0
const SEG_MALO_PALET: float = 180.0

# Para el final BUENO se necesitan las dos cosas
const NOTA_MINIMA_FINAL: float = 0.6
const HONOR_MINIMO_FINAL: int = 60

@export var puntos_honor: int = HONOR_INICIAL

var cajas_entregadas: int = 0
var tiempo_total_cajas: float = 0.0
var palets_generados: int = 0
var palets_ordenados: int = 0
var tiempo_total_palets: float = 0.0


# Compatible con npc.gd: modificar_honor(cantidad). El motivo es opcional.
func modificar_honor(cantidad: int, motivo: String = "") -> void:
	puntos_honor += cantidad
	print("🌟 [CONSECUENCIAS]: ", puntos_honor, " (", cantidad, ") ", motivo)
	honor_cambiado.emit(puntos_honor, cantidad)
	if motivo != "":
		consecuencia.emit(motivo, cantidad)


func registrar_entrega_caja(segundos: float) -> void:
	cajas_entregadas += 1
	tiempo_total_cajas += segundos


func registrar_palet_generado(n: int = 1) -> void:
	palets_generados += n


func registrar_palet_ordenado(segundos: float) -> void:
	palets_ordenados += 1
	tiempo_total_palets += segundos


func _puntuar(promedio: float, ideal: float, malo: float) -> float:
	return clampf(1.0 - (promedio - ideal) / (malo - ideal), 0.0, 1.0)


func eficiencia_cajas() -> float:
	if cajas_entregadas == 0:
		return 0.0
	return _puntuar(tiempo_total_cajas / cajas_entregadas, SEG_IDEAL_CAJA, SEG_MALO_CAJA)


# -1.0 = no aplica (nunca hubo palets)
func eficiencia_palets() -> float:
	if palets_generados == 0:
		return -1.0
	if palets_ordenados == 0:
		return 0.0
	var cobertura: float = float(palets_ordenados) / float(palets_generados)
	var velocidad: float = _puntuar(tiempo_total_palets / palets_ordenados, SEG_IDEAL_PALET, SEG_MALO_PALET)
	return cobertura * 0.7 + velocidad * 0.3


func eficiencia_total() -> float:
	var c: float = eficiencia_cajas()
	var p: float = eficiencia_palets()
	if p < 0.0:
		return c
	return c * 0.6 + p * 0.4


func consecuencias_normalizadas() -> float:
	return clampf(float(puntos_honor) / 150.0, 0.0, 1.0)


func evaluar_final() -> Dictionary:
	var cons: float = consecuencias_normalizadas()
	var efi: float = eficiencia_total()
	var nota: float = cons * 0.5 + efi * 0.5
	var bueno: bool = nota >= NOTA_MINIMA_FINAL and puntos_honor >= HONOR_MINIMO_FINAL
	return {
		"resultado": "bueno" if bueno else "malo",
		"nota": nota,
		"consecuencias": cons,
		"eficiencia_cajas": eficiencia_cajas(),
		"eficiencia_palets": eficiencia_palets(),
		"palets_ordenados": palets_ordenados,
		"palets_generados": palets_generados,
		"cajas": cajas_entregadas,
	}
