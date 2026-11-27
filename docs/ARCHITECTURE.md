# Архитектура

## Структура места
```
Workspace
  Map/Islands/Island1..8      острова (Ground, Dock, Nature, Arch, SpawnPad, OwnerSign, BarrierDome, DockEnd)
  Map/SkyLounge               площадка ожидания (SpawnLocation)
  Map/OceanPreview            вода для режима редактирования (удаляется при запуске)
  NPCs, Helicopters           папки для runtime-объектов
ReplicatedStorage
  Shared/                     Config, Util, Net, MapLayout, BuildRules
  Shared/Data/                Ingredients, Recipes, Furniture, Decor, Equipment, Stars, Guests, Staff,
                              Professions, Helicopters, Quests, Events
  Assets/                     Furniture/*, Decor/*, NPC/{Guest,Staff}, Helicopters/*
  Remotes/                    Request (RemoteFunction), Action, Push, Toast, Fx (RemoteEvent)
ServerScriptService
  Main                        загрузчик: Init → Start всех сервисов
  Services/                   DataService, EconomyService, MonetizationService, QuestService, EventService,
                              RestaurantService, BuildService, GuestService, KitchenService, StaffService,
                              ShopService, RatingService, BarrierService, HelicopterService, WorldService, NPCUtil
ServerStorage
  RestaurantTiers/Tier1..5    здания ресторана по уровням звёзд
StarterPlayer/StarterPlayerScripts
  ClientMain                  загрузчик клиента
  Controllers/                UI, State, HUD, MenusMain, MenusShop, Minigames, BuildController,
                              HeliController, Effects
StarterGui/Loading            экран загрузки
```

## Сервисы (сервер)
| Сервис | Отвечает за |
|---|---|
| DataService | загрузка/сохранение профилей, блокировка сессии через `UpdateAsync`, повторы, автосохранение 90 с, `BindToClose`, миграция схемы |
| EconomyService | личные деньги, бюджет ресторана (раздельно), журнал, опыт и уровни, множители, leaderstats, репликация состояния игрока |
| RestaurantService | 8 островов, захват (атомарно), команда (владелец + 1 друг), приглашения и запросы, 4 профессии, меню/цены, вклады, переименование (фильтр текста), здания, репликация |
| GuestService | группы гостей, столы, заказы, терпение, оплата, чаевые, отзывы, репутация, критики/VIP, официант-игрок |
| KitchenService | очереди кухни и бара, списание продуктов, сеансы мини-игр с серверной проверкой, автокухня, раздача, табло |
| StaffService | NPC-персонал: найм/увольнение/обучение/зарплаты/мотивация, NPC су-шеф, рабочие циклы |
| ShopService | закупка продуктов, «докупить для меню», склад, оборудование |
| BuildService | размещение/перемещение/продажа мебели и декора, красота |
| RatingService | метрики и повышение звёзд, перестройка здания |
| BarrierService | купол, серверное выталкивание игроков и вертолётов, белый список |
| HelicopterService | покупка, вызов на площадку, сетевое владение, отталкивание, очистка |
| MonetizationService | Game Pass, Developer Products, `ProcessReceipt` |
| QuestService | статистика, ежедневные/еженедельные задания, достижения (с редкими рецептами), ежедневные награды |
| EventService | случайные события, фестиваль сервера, конкурс 15 минут, глобальные лидерборды (OrderedDataStore) |
| WorldService | террейн-океан, лагуны, горы, облака, день/ночь |

## Сеть и безопасность
- Все действия клиента идут через `Remotes.Request` с **именованными обработчиками** (белый список).
  Список: AcceptInvite, AnswerJoin, BuyHelicopter, BuyIngredient, CancelInvite, ChooseRole, ClaimDaily,
  ClaimIsland, ClaimQuest, DebugBoost (только Studio), DeclineInvite, Deposit, DespawnHelicopter, FinishCook,
  FireStaff, GetWorld, GoHome, Hello, HireStaff, Invite, KickFriend, LeaveTeam, MoveItem, PlaceItem,
  PromoteStar, RefreshPasses, ReleaseIsland, RemoveItem, RenameRestaurant, RequestJoin, RestockMenu,
  SetBarrier, SetFriendSpend, SetMenu, SetWage, SetWhitelist, SpawnHelicopter, StartCook, TrainStaff,
  UpgradeEquipment, UpgradeStorage, Visit, Withdraw.
- Ограничение частоты (token bucket) на игрока и на запрос; ошибки обработчиков ловятся `pcall`.
- Аргументы очищаются: только числа (конечные), строки (≤200 символов), булевы, таблицы (≤64 ключей, глубина 4).
- Сервер **не доверяет клиенту** цены, деньги, награды, права и позиции: всё пересчитывается на сервере.
- Мини-игры: сервер выдаёт токен сеанса, проверяет число шагов, диапазон оценок и минимальное время
  (слишком быстрое завершение режет качество до 30%).
- Взаимодействия со столами/раздачей/кухней — через `ProximityPrompt` (сервер проверяет членство и профессию).
- Деньги ресторана тратит владелец; друг — только с разрешения и с дневным лимитом; вывод — только владелец.

## Данные игрока (DataStore `RIT_PlayerData_v1`, ключ `u_<UserId>`)
```
{ data = {
    schema, money, level, xp, prof = {Cook,Waiter,Chef,Director = {level,xp}},
    stats = {...}, income = [...], purchases = {[PurchaseId]=time}, purchaseOrder = [...],
    boosts = {mult, untilTime}, daily = {lastDay, streak}, quests = {...}, achievements = {...},
    helicopters = {owned, equipped}, ownedPasses, ownedFurnitureTypes, lastRole,
    restaurant = { name, stars, budget, reputation, cleanliness, inventory, storageLevel, menu,
                   unlockedRecipes, equipment, furniture, decor, staff, chefNpc, barrierOn, whitelist,
                   friendCanSpend, stats, reviews, ledger, nextUid } },
  lock = { job = JobId, time }, savedAt }
```
Ресторан хранится в профиле владельца — при выходе сохраняется, при входе восстанавливается на любом
свободном острове.

## Оптимизация
- NPC без Humanoid: якорный корень + `WeldConstraint`, движение твинами (без физики и pathfinding).
- Один цикл на сервис (1–2 Гц) обходит все 8 ресторанов; ограничение `Config.MaxGuestsGlobal = 140`.
- Состояние ресторана отправляется только членам команды, не чаще 2 раз в секунду; мир — раз в 5 с.
- Анимация винтов вертолётов и скрытие крыши — только на клиенте.
