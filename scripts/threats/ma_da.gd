extends ThreatBase
## Ma da — hồn người chết đuối, lang thang cánh phải ẩm ướt (restroom/sân nước). Đi
## lang thang ngẫu nhiên giữa các phòng cánh phải cho tới cửa phải; đóng cửa đúng bên
## đẩy nó về chỗ xuất phát. Counter = đóng cửa (như quái thường). Không còn cơ chế nước.

func _configure() -> void:
	movement_model = MODEL_WANDER
	spawn_location = MapGraph.RESTROOM
	# Giữ trong cánh phải ẩm ướt (không tràn sang cánh trái) — từ restroom nó lần được
	# tới RIGHT_DOOR qua infirmary/right_hall; courtyard/gym là vùng lảng vảng phía trên.
	wander_zone = [MapGraph.COURTYARD, MapGraph.RESTROOM, MapGraph.GYM,
		MapGraph.INFIRMARY, MapGraph.RIGHT_HALL, MapGraph.RIGHT_DOOR]
	move_interval = 3.0
	attack_time = 7.0
	via_drain_at_door = 5.0
	counter_door = true
