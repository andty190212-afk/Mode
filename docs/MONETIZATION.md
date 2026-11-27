# Game Pass и Developer Products — что создать и куда вписать ID

Все ID вписываются в `ReplicatedStorage.Shared.Config` (файл `src/ReplicatedStorage/Shared/Config.lua`).
Пока ID = 0, покупка не предлагается (в интерфейсе — сообщение «не настроено»).

## Game Pass (постоянные)
Создание: Creator Dashboard → ваш опыт → **Monetization → Passes → Create a Pass** → цена → скопируйте ID.

| Ключ в Config | Название | Цена | Что даёт |
|---|---|---|---|
| `Config.GamePasses.Chef` | Шеф-повар | **80 Robux** | Профессия «Шеф-повар»: NPC су-шеф готовит, фирменные рецепты, +10% качества |
| `Config.GamePasses.Director` | Директор ресторана | **100 Robux** | Профессия «Директор»: найм и управление NPC-персоналом, зарплаты, меню |

```lua
Config.GamePasses = {
	Chef = 1234567890,      -- ← ID Game Pass «Шеф-повар»
	Director = 1234567891,  -- ← ID Game Pass «Директор ресторана»
}
```
Проверка владения — `MarketplaceService:UserOwnsGamePassAsync` при входе и после покупки
(`PromptGamePassPurchaseFinished`). Подтверждённая покупка запоминается в профиле и используется
только если API Roblox временно недоступен.

`Config.StudioGrantGamePasses = true` открывает платные профессии **только в Roblox Studio**
(`RunService:IsStudio()`) для тестирования. На опубликованных серверах не действует.

## Developer Products (многоразовые)
Создание: Creator Dashboard → **Monetization → Developer Products → Create**.

| key | Название | Цена (R$) | Награда |
|---|---|---|---|
| `cash_small` | Горсть монет | 25 | +$1 500 |
| `cash_medium` | Мешок монет | 99 | +$7 500 |
| `cash_large` | Сундук монет | 399 | +$40 000 |
| `cash_huge` | Сокровищница | 999 | +$120 000 |
| `boost_x2_30` | Заработок x2 (30 мин) | 79 | множитель x2 на 30 минут |
| `boost_x3_30` | Заработок x3 (30 мин) | 149 | множитель x3 на 30 минут |
| `boost_x2_120` | Заработок x2 (2 часа) | 249 | множитель x2 на 120 минут |

Впишите ID в поле `id` соответствующей строки `Config.Products`. Цены/награды можно менять там же
(цена в Robux в Config используется только для отображения — реальная цена задаётся на сайте).

Множитель действует на личный заработок (зарплата, чаевые) и выручку ресторана, когда покупатель
в команде. Повторная покупка продлевает время, более сильный множитель не складывается с более слабым.

## Защита от двойного начисления
`MarketplaceService.ProcessReceipt` (`MonetizationService`):
1. игрок не на сервере / профиль не загружен → `NotProcessedYet` (Roblox повторит позже);
2. `PurchaseId` уже в `profile.purchases` → `PurchaseGranted` без повторной выдачи;
3. выдача награды → запись `PurchaseId` → **сохранение в DataStore** → только затем `PurchaseGranted`;
4. если сохранение не удалось → `NotProcessedYet` (id уже в памяти, повторная обработка не задублирует).
