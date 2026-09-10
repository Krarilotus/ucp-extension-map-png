-- Game language only: the loaded language marker (text group 6, entry 0),
-- with UCP's data.version.getGameLanguage() as fallback. Never the GUI/OS locale.
local M = {}
M.languages = {
  it = {1252, "Importa altimetria", "Esporta altimetria", "Importa terreno", "Esporta terreno", "Seleziona PNG", "PNG non valido", "Inserisci un nome"},
  pl = {1250, "Importuj wysokości", "Eksportuj wysokości", "Importuj teren", "Eksportuj teren", "Wybierz PNG", "Nieprawidłowy PNG", "Wpisz nazwę pliku"},
  en = {1252, "Import Heightmap", "Export Heightmap", "Import Terrain", "Export Terrain", "Select a PNG", "Invalid PNG", "Enter a filename"},
  de = {1252, "Höhenkarte importieren", "Höhenkarte exportieren", "Terrain importieren", "Terrain exportieren", "PNG auswählen", "Ungültige PNG", "Dateiname eingeben"},
  fr = {1252, "Importer les hauteurs", "Exporter les hauteurs", "Importer le terrain", "Exporter le terrain", "Choisir un PNG", "PNG invalide", "Saisir un nom"},
  ru = {1251, "Импорт высот", "Экспорт высот", "Импорт ландшафта", "Экспорт ландшафта", "Выберите PNG", "Неверный PNG", "Введите имя файла"},
  hu = {1250, "Magasságtérkép import", "Magasságtérkép export", "Terep importálása", "Terep exportálása", "PNG kiválasztása", "Érvénytelen PNG", "Adjon meg fájlnevet"},
  tr = {1254, "Yükseklik içe aktar", "Yükseklik dışa aktar", "Araziyi içe aktar", "Araziyi dışa aktar", "PNG seçin", "Geçersiz PNG", "Dosya adı girin"},
  ch = {936, "导入高度图", "导出高度图", "导入地形", "导出地形", "选择 PNG", "无效 PNG", "输入文件名"},
  es = {1252, "Importar alturas", "Exportar alturas", "Importar terreno", "Exportar terreno", "Elegir PNG", "PNG no válido", "Introducir nombre"},
  fa = {1256, "ورود نقشه ارتفاع", "خروجی نقشه ارتفاع", "ورود زمین", "خروجی زمین", "انتخاب PNG", "PNG نامعتبر", "نام فایل را وارد کنید"},
}


local language = "en"
local folderLabels = {en="Open folder", de="Ordner öffnen", fr="Ouvrir le dossier",
  es="Abrir carpeta", it="Apri cartella", pl="Otwórz folder", ru="Открыть папку",
  hu="Mappa megnyitása", tr="Klasörü aç", ch="打开文件夹", fa="باز کردن پوشه"}
function M.folderLabel(code) return folderLabels[code or language] or folderLabels.en end
local importWarnings = {
  en={"May cause bugs with placed", "objects and structures."},
  de={"Mögliche Fehler mit platzierten", "Objekten und Gebäuden."},
  fr={"Risque de bugs avec les objets", "et bâtiments déjà placés."},
  es={"Puede causar fallos con objetos", "y estructuras ya colocados."},
  it={"Possibili errori con oggetti", "e strutture già posizionati."},
  pl={"Możliwe błędy z umieszczonymi", "obiektami i budowlami."},
  ru={"Возможны ошибки с объектами", "и постройками на карте."},
  hu={"Hibák a már elhelyezett", "objektumokkal és épületekkel."},
  tr={"Yerleştirilmiş nesne ve yapılarda", "hatalara neden olabilir."},
  ch={"可能导致已放置的物体", "和建筑出现错误。"},
  fa={"احتمال خطا در اشیاء", "و ساختمان‌های قرارگرفته."},
}
function M.importWarning(code) return importWarnings[code or language] or importWarnings.en end
local aliases = {english="en", american="en", german="de", french="fr",
  italian="it", spanish="es", polish="pl", russian="ru", hungarian="hu",
  turkish="tr", chinese="ch", persian="fa", farsi="fa", zh="ch"}
function M.normalize(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
  value = value:match("^%s*(.-)%s*$"):gsub("_", "-")
  value = aliases[value] or aliases[value:match("^([a-z]+)%-")] or value:match("^([a-z]+)")
  return M.languages[value] and value or nil
end

function M.resolve(frameworkLanguage, loadedLanguage)
  -- Translations can use an English executable: loaded text is authoritative.
  local loaded = M.normalize(loadedLanguage)
  if loaded then return loaded, "loaded game text" end
  local framework = M.normalize(frameworkLanguage)
  if framework then return framework, "UCP game language" end
  return "en", "English fallback"
end

function M.initialize(ffi, game)
  local paths = require("mappng.paths")
  local frameworkLanguage, loadedLanguage
  local provider = data and data.version
  if provider and type(provider.getGameLanguage) == "function" then
    local ok, result = pcall(provider.getGameLanguage)
    if ok then frameworkLanguage = result end
  end
  local ok, result = pcall(function()
    local r = game.Rendering
    return ffi.string(r.getTextStringInGroupAtOffset(r.textManager, 6, 0))
  end)
  if ok then loadedLanguage = result end
  local source
  language, source = M.resolve(frameworkLanguage, loadedLanguage)
  local codepage = M.languages[language][1]
  -- Same native TextManager field used by textResourceModifier. The running
  -- game's encoding takes precedence over a language-to-codepage assumption.
  local gotCodepage, nativeCodepage = pcall(function()
    return (ffi.tonumber or tonumber)(ffi.cast("int *", game.Rendering.textManager)[4])
  end)
  if gotCodepage and ({[1250]=true,[1251]=true,[1252]=true,[1254]=true,
      [1256]=true,[936]=true,[65001]=true})[nativeCodepage] then codepage = nativeCodepage end
  paths.setGameCodepage(codepage)
  log(INFO, "map-png: dialog language " .. language .. " (" .. source .. "), codepage " .. codepage)
  if source == "English fallback" then log(WARNING, "map-png: game language unavailable or unsupported") end
end

function M.action(mode, what)
  return M.languages[language][(what == "height" and 2 or 4) + (mode == "export" and 1 or 0)]
end
function M.message(key)
  return M.languages[language][({select = 6, invalid = 7, name = 8})[key]]
end
return M
