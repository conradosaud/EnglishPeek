local ADDON, ns = ...

-- User-facing strings, picked by GetLocale(); locales without a translation fall back to enUS.
-- The ptBR block is intentionally in Portuguese (it is the Brazilian Portuguese localization).
-- To add a language, copy the enUS block under its locale code (e.g. esES, deDE) and translate it.
local strings = {
    enUS = {
        KEYBIND_NAME = "English Peek: hold to show English",
        WELCOME = "Welcome to |cff33ccffEnglish Peek|r!\n\nHold a key to see quest, item, zone, dungeon and NPC names in English.\n\nHold |cffffd100%s|r to try it, or click below to change the key.",
        WELCOME_NOKEY = "Welcome to |cff33ccffEnglish Peek|r!\n\nHold a key to see quest, item, zone, dungeon and NPC names in English.\n\nNo key is set yet: click below to choose one.",
        BTN_OK = "OK",
        BTN_CHANGE = "Change key",
        MSG_KEY_REPLACED = "F12 was assigned to \"%s\" and is now used by English Peek. You can change it in Key Bindings > AddOns.",
        BTN_MAPS = "English maps",
        MAPS_OFFER = "Optional: to also see the text painted on the world map in English, install the |cffd597ffMap Fix Forever|r addon and keep it |cffff4444disabled|r in the AddOns list (English Peek only uses its images while you hold the key).\n\nCopy the link (Ctrl+C):",
        MSG_MAPFIX_ENABLED = "Map Fix Forever is enabled and shows English maps all the time. To see them only while holding the key, disable it in the AddOns list (English Peek uses its images even when disabled).",

        DIAG_TITLE = "Status:",
        DIAG_SRC_NORMAL = "usual location",
        DIAG_SRC_ALT = "found in an alternative location (Questie changed)",
        DIAG_SRC_NONE = "not found",
        DIAG_ENGLISH = "The game is in English: the key does nothing (there is nothing to translate).",
        DIAG_QDB_OK = "QuestieDB: quests, items, NPCs and objects OK.",
        DIAG_QDB_CONTRACT = "QuestieDB responds, but its version is newer than this addon expects (it may still work).",
        DIAG_QDB_FAIL = "QuestieDB is not responding: quests, items, NPCs and objects will not be translated.",
        DIAG_ZONES = "Zones: %d names (%s).",
        DIAG_ZONES_FAIL = "Zones: Questie zone table not found. Zones will not be translated.",
        DIAG_TERMS = "Classes, races, professions, weapons: %d terms (%s).",
        DIAG_CONTINENTS = "Continents: %s.",
        DIAG_ZONEDB = "Map names (ZoneDB): %s.",
        DIAG_OBJECTS = "World objects: %d names.",
        DIAG_OBJECTS_BUILDING = "World objects: indexing in background (%d / %d).",
        DIAG_KEY = "Key: %s.",
        DIAG_NOKEY = "No key set: Key Bindings > AddOns > English Peek.",
        DIAG_MAPS_MISSING = "Map art in English: Map Fix Forever not installed (optional, see /englishpeek).",
        DIAG_MAPS_ENABLED = "Map art in English: Map Fix Forever is ENABLED (disable it to see English maps only with the key).",
        DIAG_MAPS_OK = "Map art in English: OK (Map Fix Forever images).",
        DIAG_LOGIN_WARN = "Some translations are not working (Questie may have changed). Type /englishpeek status for details.",
    },
    ptBR = {
        KEYBIND_NAME = "English Peek: segurar para ver em inglês",
        WELCOME = "Bem-vindo ao |cff33ccffEnglish Peek|r!\n\nSegure uma tecla para ver nomes de missões, itens, regiões, masmorras e NPCs em inglês.\n\nSegure |cffffd100%s|r para experimentar, ou clique abaixo para alterar a tecla.",
        WELCOME_NOKEY = "Bem-vindo ao |cff33ccffEnglish Peek|r!\n\nSegure uma tecla para ver nomes de missões, itens, regiões, masmorras e NPCs em inglês.\n\nNenhuma tecla definida ainda: clique abaixo para escolher.",
        BTN_OK = "OK",
        BTN_CHANGE = "Alterar tecla",
        MSG_KEY_REPLACED = "F12 estava em \"%s\" e agora é usada pelo English Peek. Você pode alterar em Teclas > AddOns.",
        BTN_MAPS = "Mapas em inglês",
        MAPS_OFFER = "Opcional: para ver também o texto pintado no mapa-múndi em inglês, instale o addon |cffd597ffMap Fix Forever|r e deixe-o |cffff4444desativado|r na lista de AddOns (o English Peek só usa as imagens dele enquanto você segura a tecla).\n\nCopie o link (Ctrl+C):",
        MSG_MAPFIX_ENABLED = "O Map Fix Forever está ativado e mostra os mapas em inglês o tempo todo. Para vê-los só ao segurar a tecla, desative-o na lista de AddOns (o English Peek usa as imagens dele mesmo desativado).",

        DIAG_TITLE = "Status:",
        DIAG_SRC_NORMAL = "local habitual",
        DIAG_SRC_ALT = "encontrado em local alternativo (o Questie mudou)",
        DIAG_SRC_NONE = "não encontrado",
        DIAG_ENGLISH = "O jogo está em inglês: a tecla não faz nada (não há o que traduzir).",
        DIAG_QDB_OK = "QuestieDB: missões, itens, NPCs e objetos OK.",
        DIAG_QDB_CONTRACT = "QuestieDB responde, mas a versão dele é mais nova do que este addon espera (pode continuar funcionando).",
        DIAG_QDB_FAIL = "QuestieDB não responde: missões, itens, NPCs e objetos não serão traduzidos.",
        DIAG_ZONES = "Regiões: %d nomes (%s).",
        DIAG_ZONES_FAIL = "Regiões: tabela de zonas do Questie não encontrada. Regiões não serão traduzidas.",
        DIAG_TERMS = "Classes, raças, profissões, armas: %d termos (%s).",
        DIAG_CONTINENTS = "Continentes: %s.",
        DIAG_ZONEDB = "Nomes de mapas (ZoneDB): %s.",
        DIAG_OBJECTS = "Objetos do mundo: %d nomes.",
        DIAG_OBJECTS_BUILDING = "Objetos do mundo: indexando em segundo plano (%d / %d).",
        DIAG_KEY = "Tecla: %s.",
        DIAG_NOKEY = "Nenhuma tecla definida: Teclas > AddOns > English Peek.",
        DIAG_MAPS_MISSING = "Arte do mapa em inglês: Map Fix Forever não instalado (opcional, veja /englishpeek).",
        DIAG_MAPS_ENABLED = "Arte do mapa em inglês: Map Fix Forever está ATIVADO (desative para ver os mapas em inglês só com a tecla).",
        DIAG_MAPS_OK = "Arte do mapa em inglês: OK (imagens do Map Fix Forever).",
        DIAG_LOGIN_WARN = "Algumas traduções não estão funcionando (o Questie pode ter mudado). Digite /englishpeek status para detalhes.",
    },
}

ns.L = setmetatable({}, {
    __index = function(_, key)
        local loc = strings[GetLocale()]
        return (loc and loc[key]) or strings.enUS[key] or key
    end,
})
