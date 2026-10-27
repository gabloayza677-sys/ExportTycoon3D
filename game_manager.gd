extends Node
# ============================================================
# game_manager.gd
# Va en: res://game_manager.gd
# Registrado en Proyecto > Configuración del proyecto > Globales
# con el nombre exacto: GameManager
# ============================================================

const UiJuego = preload("res://ui_juego.gd")
const EventosMes = preload("res://eventos_mes.gd")
const HudEstado = preload("res://hud_estado.gd")
const MundoMes = preload("res://mundo_mes.gd")

@export var mes_actual: int = 1
@export var cajas_procesadas_mes: int = 0
@export var cajas_meta_mes: int = 240 # El generador lo ajusta solo (= cajas generadas)
@export var mostrar_intro: bool = true # Pantalla negra "MES 1" al iniciar el juego
@export var eventos_automaticos: bool = true # Minievento al inicio de cada mes
@export var teclas_de_prueba: bool = true # F9 = saltar al siguiente mes (ponlo en false al terminar)

# true mientras dura la transición: no se pueden recoger cajas
var en_transicion: bool = false

# Interfaz de transiciones, minieventos, HUD minimalista y mundo (edificio + mecánicas por mes)
var ui = null
var eventos = null
var hud = null
var mundo = null

# Punto de aparición del jugador (se guarda al iniciar el juego)
var spawn_guardado: bool = false
var spawn_transform: Transform3D = Transform3D.IDENTITY
var _spawn_rot_camara: Vector3 = Vector3.ZERO

# Para medir la eficiencia: segundos entre una entrega y la siguiente
var _t_ultima_entrega: float = 0.0
var _final_en_curso: bool = false


func _ready() -> void:
	ui = UiJuego.new()
	add_child(ui)
	eventos = EventosMes.new()
	add_child(eventos)
	hud = HudEstado.new()
	add_child(hud)
	mundo = MundoMes.new()
	add_child(mundo)

	en_transicion = true
	if mostrar_intro:
		get_tree().paused = true
		ui.poner_negro(mes_actual)

	# Esperamos a que la escena principal ya exista
	await get_tree().process_frame
	await get_tree().process_frame
	_guardar_spawn()
	await mundo.iniciar()

	if mostrar_intro:
		await ui.mantener_y_aclarar(1.2)
		get_tree().paused = false

	# Minievento automático del Mes 1
	_congelar_jugador(true)
	await _correr_evento_del_mes()
	_congelar_jugador(false)
	en_transicion = false
	_comenzar_mes_activo()


func _unhandled_input(event: InputEvent) -> void:
	if not teclas_de_prueba or en_transicion:
		return
	var tecla := event as InputEventKey
	if tecla != null and tecla.pressed and not tecla.echo and tecla.keycode == KEY_F9:
		print("🧪 [PRUEBA] Saltando al siguiente mes (F9)")
		iniciar_transicion_mes()


# ------------------------------------------------------------
# REGLAS DEL MES (para generador_cajas.gd, caja.gd, area_3d.gd...)
# ------------------------------------------------------------
# Ej.: if GameManager.regla("cajas_en_piso", false): ...
func regla(clave: String, defecto: Variant = null) -> Variant:
	if mundo == null:
		return defecto
	return mundo.regla(mes_actual, clave, defecto)


# false durante el apagón si el jugador no tiene la linterna equipada.
# Úsalo en el código de recoger/entregar cajas.
func puede_interactuar() -> bool:
	if mundo == null:
		return true
	return mundo.puede_interactuar()


# ------------------------------------------------------------
# CONTEO DE CAJAS (se llama al entregar una caja en el camión)
# ------------------------------------------------------------
func registrar_caja_colocada() -> void:
	if en_transicion:
		return

	var ahora: float = Time.get_ticks_msec() / 1000.0
	HonorManager.registrar_entrega_caja(minf(ahora - _t_ultima_entrega, 60.0))
	_t_ultima_entrega = ahora

	cajas_procesadas_mes += 1
	print("📦 Cajas gestionadas este mes: ", cajas_procesadas_mes, " / ", cajas_meta_mes)

	comprobar_fin_de_mes()


func comprobar_fin_de_mes() -> void:
	if en_transicion:
		return
	if cajas_procesadas_mes < cajas_meta_mes:
		return
	
	# NUEVO: desde el mes 10 también deben estar ordenados TODOS los palets
	if mundo != null and not mundo.mes_completable():
		mundo.avisar_palets_pendientes()
		return

	iniciar_transicion_mes()


func _comenzar_mes_activo() -> void:
	_t_ultima_entrega = Time.get_ticks_msec() / 1000.0
	mundo.comenzar_mes_activo()


# ------------------------------------------------------------
# TRANSICIÓN DE MES
# ------------------------------------------------------------
func iniciar_transicion_mes() -> void:
	cajas_procesadas_mes = 0

	# MES 12 COMPLETADO: llega el jefe y se evalúa todo
	if mes_actual >= 12:
		if _final_en_curso:
			return
		_final_en_curso = true
		en_transicion = true
		_congelar_jugador(true)
		print("🏆 ¡HAS COMPLETADO LOS 12 MESES! Evaluación final del jefe...")
		await mundo.auditoria_final()
		return

	var mes_anterior: int = mes_actual
	var nuevo_mes: int = mes_actual + 1
	en_transicion = true
	get_tree().paused = true # congela al jugador durante la transición

	# 1. Pantalla negra progresiva con "MES 1"
	await ui.fundido_a_negro(mes_anterior)
	await get_tree().create_timer(0.6).timeout

	# 2. "MES 1" cambia a "MES 2"
	await ui.cambiar_mes_en_pantalla(nuevo_mes)

	# 3. Con la pantalla negra: spawn + cajas nuevas + NPC del mes en su puesto
	await _aplicar_cambio_de_mes(nuevo_mes)
	await get_tree().create_timer(0.8).timeout

	# 4. Se aclara la pantalla
	await ui.aclarar()
	get_tree().paused = false
	_congelar_jugador(true) # tú te quedas quieto mientras pasa el evento

	# 5. El NPC del mes (si hay) sale caminando hacia ti MIENTRAS ocurre el minievento
	var npc = _buscar_npc_con_dilema()
	var estado: Dictionary = {"npc_listo": npc == null}
	if npc:
		var caminar = func() -> void:
			await npc.caminar_hacia_jugador()
			estado["npc_listo"] = true
		caminar.call()

	await _correr_evento_del_mes()

	var limite: int = Time.get_ticks_msec() + 15000
	while not estado["npc_listo"] and Time.get_ticks_msec() < limite:
		await get_tree().process_frame

	# 6. El NPC te hace su pregunta de honor
	if npc:
		await npc.iniciar_dialogo()

	_congelar_jugador(false)
	get_tree().paused = false
	en_transicion = false
	_comenzar_mes_activo()


func _correr_evento_del_mes() -> void:
	if not eventos_automaticos or eventos == null:
		return
	await eventos.ejecutar(mes_actual)


func _aplicar_cambio_de_mes(nuevo_mes: int) -> void:
	mes_actual = nuevo_mes
	print("\n========================================")
	print("🎉 ¡META ALCANZADA! Entrando al Mes ", mes_actual)
	print("========================================")

	# Bajar del montacargas y soltar la caja de las manos por si acaso
	mundo.desmontar_montacargas()
	var mano = get_tree().root.find_child("CajaEnMano", true, false)
	if mano:
		mano.visible = false

	# 1. Volver al spawn
	_llevar_jugador_al_spawn()

	# 2. Mostrar/ocultar NPCs según el nuevo mes
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.has_method("comprobar_visibilidad"):
			npc.comprobar_visibilidad()

	# 3. Volver a llenar los estantes
	for generador in get_tree().get_nodes_in_group("generadores_cajas"):
		if generador.has_method("generar_almacen_industrial"):
			generador.generar_almacen_industrial()

	# 4. Mecánicas del mes (goteras, apagón, alarma, auditores, estantes extra, montacargas...)
	await mundo.aplicar_mes(nuevo_mes)

	# 5. Luces y efectos del mes
	notificar_eventos_escena()


func _buscar_npc_con_dilema() -> Node:
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.has_method("tiene_dilema_pendiente") and npc.tiene_dilema_pendiente():
			return npc
	return null


# ------------------------------------------------------------
# JUGADOR: SPAWN Y CONGELADO
# ------------------------------------------------------------
func _guardar_spawn() -> void:
	var jugador := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	if jugador == null:
		push_warning("No encontré el nodo 'Player': no se podrá volver al spawn.")
		return

	spawn_transform = jugador.global_transform
	var camara := jugador.get_node_or_null("Camera3D") as Camera3D
	if camara:
		_spawn_rot_camara = camara.rotation
	spawn_guardado = true
	print("📍 Spawn guardado en: ", spawn_transform.origin)


func _llevar_jugador_al_spawn() -> void:
	if not spawn_guardado:
		return
	var jugador := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	if jugador == null:
		return

	jugador.global_transform = spawn_transform
	jugador.velocity = Vector3.ZERO
	var camara := jugador.get_node_or_null("Camera3D") as Camera3D
	if camara:
		camara.rotation = _spawn_rot_camara


func _congelar_jugador(congelar: bool) -> void:
	var jugador := get_tree().root.find_child("Player", true, false)
	if jugador:
		jugador.process_mode = Node.PROCESS_MODE_DISABLED if congelar else Node.PROCESS_MODE_INHERIT


# ------------------------------------------------------------
# EVENTOS DE ESCENA
# ------------------------------------------------------------
func notificar_eventos_escena() -> void:
	var luz_principal = get_tree().root.find_child("DirectionalLight3D", true, false)
	if luz_principal and luz_principal.has_method("actualizar_iluminacion"):
		luz_principal.actualizar_iluminacion()

	get_tree().call_group("eventos_clima", "verificar_evento")
