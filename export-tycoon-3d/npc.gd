extends StaticBody3D
# ============================================================
# npc.gd
# Va en: nodo raíz (StaticBody3D) de npc.tscn
# ============================================================

# Datos de los 5 personajes. En el Inspector solo eliges "Personaje".
const PERSONAJES: Dictionary = {
	"Don Mateo": {
		"mes": 2,
		"nombre": "Don Mateo",
		"rol": "Inspector de Calidad",
		"situacion": "Encontré cajas húmedas en las repisas. ¿Las reempacamos o las mandamos así?",
		"etica": "1. Reempacar todo correctamente (+ Honor)",
		"atajo": "2. Despachar igual para cumplir la meta (- Honor)",
		"honor_etico": 15,
		"honor_atajo": -10,
		"color": "#8c5a33",
	},
	"Carlos": {
		"mes": 4,
		"nombre": "Carlos",
		"rol": "Representante de Operarios",
		"situacion": "El personal está agotado por doblar turno para ordenar las cajas. ¿Damos descanso o exigimos más?",
		"etica": "1. Dar descansos y turnos rotativos con horas extras justas (+ Honor)",
		"atajo": "2. Exigir trabajo bajo presión sin compensación (- Honor)",
		"honor_etico": 15,
		"honor_atajo": -10,
		"color": "#e08a1e",
	},
	"Sofía": {
		"mes": 7,
		"nombre": "Sofía",
		"rol": "Jefa de Logística",
		"situacion": "Un transportista con sobrepeso me ofrece dinero por firmar la salida sin pasar por la báscula. ¿Qué hago?",
		"etica": "1. Rechazar el soborno y obligarlo a descargar el exceso (+ Honor)",
		"atajo": "2. Aceptar el trato y firmar la salida (- Honor)",
		"honor_etico": 20,
		"honor_atajo": -15,
		"color": "#c4337f",
	},
	"Galarza": {
		"mes": 9,
		"nombre": "Ing. Galarza",
		"rol": "Especialista en Seguridad",
		"situacion": "Los soportes de las estanterías muestran una deformación por exceso de peso. ¿Reducimos la carga?",
		"etica": "1. Detener la sección y reforzar los soportes (+ Honor)",
		"atajo": "2. Ignorar la advertencia y seguir apilando peso (- Honor)",
		"honor_etico": 30,
		"honor_atajo": -25,
		"color": "#e6d726",
	},
	"Rivas": {
		"mes": 11,
		"nombre": "Lic. Rivas",
		"rol": "Auditor Financiero",
		"situacion": "El proveedor nos facturó con un descuento indebido a nuestro favor y no se ha dado cuenta. ¿Qué hacemos?",
		"etica": "1. Avisar al proveedor y pagar el monto justo (+ Honor)",
		"atajo": "2. Guardar silencio y quedarnos con el dinero (- Honor)",
		"honor_etico": 25,
		"honor_atajo": -20,
		"color": "#336bcc",
	},
}

@export_category("0. Personaje")
## Elige el personaje y se rellenan solos: mes, textos, honor y color.
## "Personalizado" usa los campos de la sección 1.
@export_enum("Don Mateo", "Carlos", "Sofía", "Galarza", "Rivas", "Personalizado") var personaje: String = "Don Mateo"

@export_category("1. Datos (solo si Personaje = Personalizado)")
@export var mes_activacion: int = 2
@export var nombre_npc: String = "Don Mateo"
@export var rol_npc: String = "Inspector de Calidad"
@export_multiline var situacion_texto: String = "Encontré cajas húmedas en las repisas. ¿Las reempacamos o las mandamos así?"
@export var texto_opcion_etica: String = "1. Reempacar todo correctamente (+ Honor)"
@export var texto_opcion_rapida: String = "2. Despachar igual para cumplir la meta (- Honor)"
@export var puntos_honor_etico: int = 15
@export var puntos_honor_rapido: int = -10
@export var color_npc: Color = Color(0.55, 0.35, 0.2)

@export_category("2. Cómo sale al encuentro")
## true = sale desde donde lo dejaste en el editor 3D.
## false = sale automáticamente desde "distancia_salida" metros delante del jugador.
@export var salir_desde_el_editor: bool = true
@export var distancia_salida: float = 10.0
## A cuántos metros del jugador se detiene para hablar.
@export var distancia_frente: float = 2.5
@export var velocidad_caminata: float = 2.5

var posicion_en_base: Vector3 # Sitio donde lo dejaste en el editor (también se usa su altura Y)
var ya_interactuo: bool = false
var _malla_y0: float = 0.0

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var malla: MeshInstance3D = get_node_or_null("MeshInstance3D")


func _ready() -> void:
	if not is_in_group("npcs"):
		add_to_group("npcs")

	_aplicar_personaje()
	posicion_en_base = global_position
	if malla:
		_malla_y0 = malla.position.y
	_crear_apariencia()
	comprobar_visibilidad()


# ------------------------------------------------------------
# PERSONAJE Y APARIENCIA
# ------------------------------------------------------------
func _aplicar_personaje() -> void:
	if not PERSONAJES.has(personaje):
		return # "Personalizado": se usan los campos del Inspector

	var d: Dictionary = PERSONAJES[personaje]
	mes_activacion = d["mes"]
	nombre_npc = d["nombre"]
	rol_npc = d["rol"]
	situacion_texto = d["situacion"]
	texto_opcion_etica = d["etica"]
	texto_opcion_rapida = d["atajo"]
	puntos_honor_etico = d["honor_etico"]
	puntos_honor_rapido = d["honor_atajo"]
	color_npc = Color.html(d["color"])


func _crear_apariencia() -> void:
	# Color propio para distinguirlos + "visor" para ver hacia dónde mira
	if malla:
		var material := StandardMaterial3D.new()
		material.albedo_color = color_npc
		malla.material_override = material

		var visor := MeshInstance3D.new()
		var caja := BoxMesh.new()
		caja.size = Vector3(0.5, 0.14, 0.25)
		visor.mesh = caja
		var material_visor := StandardMaterial3D.new()
		material_visor.albedo_color = Color(0.05, 0.05, 0.08)
		visor.material_override = material_visor
		visor.position = Vector3(0, 0.55, -0.42)
		malla.add_child(visor)

	# Nombre flotando sobre su cabeza
	var etiqueta := Label3D.new()
	etiqueta.text = nombre_npc + "\n" + rol_npc
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.font_size = 48
	etiqueta.pixel_size = 0.005
	etiqueta.outline_size = 12
	etiqueta.modulate = color_npc.lightened(0.35)
	etiqueta.position = Vector3(0, 1.6, 0)
	add_child(etiqueta)


# ------------------------------------------------------------
# VISIBILIDAD SEGÚN EL MES
# ------------------------------------------------------------
func comprobar_visibilidad() -> void:
	var es_mi_mes: bool = GameManager.mes_actual == mes_activacion and not ya_interactuo

	if es_mi_mes:
		global_position = _posicion_de_salida()
		if GameManager.spawn_guardado:
			_mirar_hacia(GameManager.spawn_transform.origin)
		show()
		process_mode = Node.PROCESS_MODE_INHERIT
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		print("✨ [NPC APARECIÓ]: ", nombre_npc, " ha aparecido para el Mes ", mes_activacion)
	else:
		hide()
		process_mode = Node.PROCESS_MODE_DISABLED
		if collision_shape:
			collision_shape.set_deferred("disabled", true)


func tiene_dilema_pendiente() -> bool:
	return visible and not ya_interactuo and GameManager.mes_actual == mes_activacion


# ------------------------------------------------------------
# CAMINAR Y HABLAR
# ------------------------------------------------------------
func caminar_hacia_jugador() -> void:
	if not GameManager.spawn_guardado:
		return
	await _caminar_a(_punto_frente_al_jugador())
	_mirar_hacia(GameManager.spawn_transform.origin)


func iniciar_dialogo() -> void:
	if ya_interactuo:
		return

	var ui = GameManager.ui
	var es_etico: bool = await ui.mostrar_dilema(nombre_npc, rol_npc, situacion_texto, texto_opcion_etica, texto_opcion_rapida)

	resolver_decision(es_etico)

	var puntos: int = puntos_honor_etico if es_etico else puntos_honor_rapido
	await ui.cerrar_dilema(es_etico, puntos)

	# Se va caminando a su puesto (sin bloquear al jugador)
	_retirarse()


func resolver_decision(es_etico: bool) -> void:
	ya_interactuo = true
	if es_etico:
		HonorManager.modificar_honor(puntos_honor_etico)
		print("✅ Decisión ética tomada en el Mes ", mes_activacion)
	else:
		HonorManager.modificar_honor(puntos_honor_rapido)
		print("⚠️ Atajo tomado en el Mes ", mes_activacion)


func _retirarse() -> void:
	await _caminar_a(_posicion_de_salida())
	comprobar_visibilidad() # ya_interactuo = true -> se oculta


# ------------------------------------------------------------
# MOVIMIENTO
# ------------------------------------------------------------
func _caminar_a(destino: Vector3) -> void:
	var distancia: float = global_position.distance_to(destino)
	if distancia < 0.05:
		return

	_mirar_hacia(destino)
	var duracion: float = distancia / maxf(velocidad_caminata, 0.1)
	var pasos: float = distancia / 1.4 # un paso cada ~1.4 metros

	var t := create_tween().set_parallel(true)
	t.tween_property(self, "global_position", destino, duracion)
	t.tween_method(_balanceo, 0.0, pasos * PI, duracion)
	await t.finished
	_balanceo(0.0)


func _balanceo(fase: float) -> void:
	# Pequeño rebote y vaivén al caminar
	if malla == null:
		return
	malla.position.y = _malla_y0 + absf(sin(fase)) * 0.12
	malla.rotation.z = sin(fase) * 0.07


func _mirar_hacia(punto: Vector3) -> void:
	var objetivo := Vector3(punto.x, global_position.y, punto.z)
	if global_position.distance_to(objetivo) > 0.01:
		look_at(objetivo, Vector3.UP)


func _frente_del_spawn() -> Vector3:
	var f: Vector3 = -GameManager.spawn_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _punto_frente_al_jugador() -> Vector3:
	var p: Vector3 = GameManager.spawn_transform.origin + _frente_del_spawn() * distancia_frente
	return Vector3(p.x, posicion_en_base.y, p.z)


func _posicion_de_salida() -> Vector3:
	if salir_desde_el_editor or not GameManager.spawn_guardado:
		return posicion_en_base
	var p: Vector3 = GameManager.spawn_transform.origin + _frente_del_spawn() * distancia_salida
	return Vector3(p.x, posicion_en_base.y, p.z)
