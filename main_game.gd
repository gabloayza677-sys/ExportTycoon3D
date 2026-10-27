extends Node3D

@onready var lbl_dinero: Label = $CanvasLayer/Panel/LblDinero
@onready var lbl_honor: Label = $CanvasLayer/Panel/LblHonor
@onready var lbl_reputacion: Label = $CanvasLayer/Panel/LblReputacion
@onready var lbl_exitos: Label = $CanvasLayer/Panel/LblExitos
@onready var lbl_semanas: Label = $CanvasLayer/Panel/LblSemanas
@onready var lbl_mes: Label = $CanvasLayer/Panel/LblMes

func _ready() -> void:
	actualizar_ui()

func actualizar_ui() -> void:
	if lbl_dinero:
		lbl_dinero.text = "DINERO: $" + str(GameManager.dinero)
	if lbl_honor:
		lbl_honor.text = "HONOR: " + str(GameManager.honor) + "%"
	if lbl_reputacion:
		lbl_reputacion.text = "REPUTACIÓN: " + str(GameManager.reputacion)
	if lbl_exitos:
		lbl_exitos.text = "ÉXITOS: " + str(GameManager.total_exitos) + " / 240"
	if lbl_semanas:
		# Muestra las semanas restantes dentro del mes actual (4 semanas por mes)
		var semanas_restantes = 4 - (GameManager.semanas_pasadas % 4)
		lbl_semanas.text = "SEMANAS RESTANTES: " + str(semanas_restantes)
	if lbl_mes:
		lbl_mes.text = "MES: " + str(GameManager.mes_actual) + " / 12"
