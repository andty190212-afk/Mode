# Публикация игры

1. **Откройте** `dist/RestaurantIslandTycoon.rbxl` в Roblox Studio.
2. **File → Publish to Roblox As…** → «Create new experience» → название *Restaurant Island Tycoon*,
   жанр *Simulation/Tycoon*, устройства: Computer, Phone, Tablet, Console.
3. **Game Settings**:
   - *Security* → включите **Enable Studio Access to API Services** (для теста сохранений в Studio).
   - *Places → (ваше место) → Max Players*: **16** (8 ресторанов × 2 игрока). Server fill: *Roblox optimized*.
   - *Avatar*: R15 или R6 — оба поддерживаются.
   - *Communication / Privacy*: по желанию.
4. **Монетизация**: создайте 2 Game Pass и 7 Developer Products и впишите ID — см. [MONETIZATION.md](MONETIZATION.md).
   После правки `Config` снова опубликуйте (`File → Publish to Roblox`).
5. **Звуки и музыка** (необязательно): впишите ID аудио — см. [EXTERNAL_RESOURCES.md](EXTERNAL_RESOURCES.md).
6. **Иконка и миниатюры**: Creator Dashboard → Places → Thumbnails. Можно сделать скриншоты в Studio.
7. **Анкета возрастного рейтинга** (Experience Questionnaire) — обязательна для публичного доступа.
8. **Сделайте игру публичной**: Creator Dashboard → *Privacy → Public*.
9. Проверьте на реальном сервере с другом: приглашения, профессии, сохранения, покупки.

## Важное
- Данные хранятся в DataStore `RIT_PlayerData_v1` (ключи `u_<UserId>`). Если когда-нибудь понадобится
  несовместимо изменить формат — меняйте `Config.DataStoreName`, а не удаляйте данные.
- `Config.StudioGrantGamePasses` безопасен для публикации (действует только в Studio).
- `StreamingEnabled` выключен намеренно (карта небольшая, ~8 300 деталей); при желании можно включить,
  клиентский код не полагается на наличие далёких частей карты.
- Обновления кода: правьте `src/` и пересоберите (`./tools/package.sh`) **или** правьте прямо в Studio.
  Если правите в Studio — экспортируйте скрипты обратно в `src/`, чтобы не потерять изменения при пересборке
  (или используйте Rojo: `rojo serve default.project.json` синхронизирует `src/` со Studio; карта и модели
  при этом остаются в файле места).
