import Foundation

/// Every tool name the Play build knows (docs/evidence/play-964d7bec-tool-names.json:
/// prompts/tools/*.md @964d7bec, Play's knownToolNames()). Play's SkillDrafter.validate
/// accepts a skill that mentions any of them, so a skill shared from Play imports
/// here too; tools this device lacks get Play's note when the skill is read
/// (ChatSkillCatalog.unavailableToolsNote).
public enum PlaySkillToolNames {
    public static let known: Set<String> = [
        "ask_user", "clear_text", "describe", "diagnose", "do_steps", "end_not_done", "find_visually",
        "hand_to_user", "handle_obstacle", "history_read", "knowledge_read", "knowledge_search", "list_elements",
        "memory_forget", "memory_save", "memory_search", "phone_add_calendar_event", "phone_app_after_task",
        "phone_back", "phone_clear_text", "phone_collect", "phone_dialog", "phone_event", "phone_extract",
        "phone_find", "phone_gesture", "phone_launch_app", "phone_list_apps", "phone_observe", "phone_open_link",
        "phone_query", "phone_run", "phone_scroll", "phone_set_alarm", "phone_set_timer", "phone_set_wheel",
        "phone_share_text", "phone_show_alarms", "phone_system_command", "phone_type_text", "phone_wait",
        "press_key", "profile_edit", "read_file", "request_confirmation", "root_run_command", "run_bundled_script",
        "run_command", "schedule_task", "screenshot", "scroll", "search_files", "settings_list", "settings_set",
        "share_file", "skill_read", "skill_save", "skill_search", "spawn_agent", "swipe", "tap", "type_text",
        "view_past_screens", "view_user_screen", "wait", "web_back", "web_capture", "web_downloads",
        "web_evaluate_js", "web_interact", "web_keep_open", "web_navigate", "web_observe", "web_read_page",
        "web_run_site_command", "web_script", "web_site_mode", "web_tabs", "web_upload", "web_wait_for",
        "write_file"
    ]
}
