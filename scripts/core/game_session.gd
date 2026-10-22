# 只保存本次游玩状态；持久进度由 GameState.save_data 负责。
extends RefCounted

enum Phase { READING, ARRANGING, DECIDING, REVIEWING, RESULT }
var phase := Phase.READING
var current_level_id := "0001"
var current_row := "L"
var sequences: Dictionary = {}
var sequences_level := ""
var verdicts: Dictionary = {}
var review_letter := false
var review_queue: Array = []
var first_entry_level := false
