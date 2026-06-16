module Update.Expenses exposing
    ( Config
    , cancelEdit
    , delete
    , edit
    , handleEventsLoaded
    , handleGeneratedId
    , requestId
    )

import Accounting
import Events
import Json.Decode as Decode
import Model exposing (Model, TutorialState(..), TutorialStep(..))
import Projector


type alias Config msg =
    { generateExpenseId : Cmd msg
    , appendEvent : String -> Events.Event -> Cmd msg
    , saveLastAccount : String -> String -> Cmd msg
    , navigateTutorial : TutorialStep -> Model -> ( Model, Cmd msg )
    , completeTutorial : Cmd msg
    }


requestId : Config msg -> Model -> ( Model, Cmd msg )
requestId config model =
    ( model, config.generateExpenseId )


handleGeneratedId : Config msg -> Decode.Value -> Model -> ( Model, Cmd msg )
handleGeneratedId config value model =
    case Decode.decodeValue Decode.string value of
        Ok expenseId ->
            createOrUpdateExpense config expenseId model

        Err error ->
            ( { model | error = Decode.errorToString error }, Cmd.none )


createOrUpdateExpense : Config msg -> String -> Model -> ( Model, Cmd msg )
createOrUpdateExpense config expenseId model =
    let
        readyModel =
            Model.ensureSelectedAccount model

        rate =
            case readyModel.form.editingId of
                Just editingId ->
                    case List.head (List.filter (\expense -> expense.id == editingId) readyModel.expenses) of
                        Just expense ->
                            expense.exchangeRate

                        Nothing ->
                            readyModel.exchangeRate

                Nothing ->
                    readyModel.exchangeRate
    in
    case Accounting.buildExpense rate expenseId (Model.activeAccounts readyModel) readyModel.form of
        Ok expense ->
            persistExpense config readyModel expense

        Err error ->
            ( { readyModel | error = error }, Cmd.none )


persistExpense : Config msg -> Model -> Accounting.Expense -> ( Model, Cmd msg )
persistExpense config readyModel expense =
    let
        ( event, updatedModel ) =
            case readyModel.form.editingId of
                Just editingId ->
                    let
                        updateEvent =
                            Events.MovementUpdatedEvent 0
                                { movementId = editingId
                                , movementType = expense.movementType
                                , description = expense.description
                                , accountId = expense.accountId
                                , accountName = expense.accountName
                                , inputAmount = expense.inputAmount
                                , inputCurrency = expense.inputCurrency
                                , exchangeRate = expense.exchangeRate
                                , ars = expense.ars
                                , usd = expense.usd
                                , date = expense.date
                                }

                        updatedExpenses =
                            List.map
                                (\existing ->
                                    if existing.id == editingId then
                                        expense

                                    else
                                        existing
                                )
                                readyModel.expenses
                    in
                    ( updateEvent
                    , { readyModel
                        | events = updateEvent :: readyModel.events
                        , expenses = Model.activeExpenses updatedExpenses
                      }
                    )

                Nothing ->
                    let
                        createEvent =
                            Events.MovementCreatedEvent 0
                                { id = expense.id
                                , movementType = expense.movementType
                                , description = expense.description
                                , accountId = expense.accountId
                                , accountName = expense.accountName
                                , inputAmount = expense.inputAmount
                                , inputCurrency = expense.inputCurrency
                                , exchangeRate = expense.exchangeRate
                                , ars = expense.ars
                                , usd = expense.usd
                                , date = expense.date
                                }
                    in
                    ( createEvent
                    , { readyModel
                        | events = createEvent :: readyModel.events
                        , expenses = expense :: Model.activeExpenses readyModel.expenses
                      }
                    )

        isNewExpense =
            readyModel.form.editingId == Nothing

        ( modelAfterAdvance, advanceCmd ) =
            if isNewExpense then
                case updatedModel.tutorialState of
                    TutorialOpen FirstExpenseStep ->
                        config.navigateTutorial DeleteExpenseStep { updatedModel | tutorialExpenseId = Just expense.id }

                    _ ->
                        ( updatedModel, Cmd.none )

            else
                ( updatedModel, Cmd.none )
    in
    ( { modelAfterAdvance
        | form =
            { description = ""
            , amount = ""
            , accountId = readyModel.form.accountId
            , currency = readyModel.form.currency
            , date = readyModel.form.date
            , movementType = readyModel.form.movementType
            , editingId = Nothing
            }
        , error = ""
      }
    , Cmd.batch
        [ config.appendEvent readyModel.currentLedgerId event
        , config.saveLastAccount readyModel.currentLedgerId readyModel.form.accountId
        , advanceCmd
        ]
    )


delete : Config msg -> String -> Model -> ( Model, Cmd msg )
delete config movementId model =
    let
        isTutorialDelete =
            case ( model.tutorialState, model.tutorialExpenseId ) of
                ( TutorialOpen DeleteExpenseStep, Just tutorialExpenseId ) ->
                    tutorialExpenseId == movementId

                _ ->
                    False

        event =
            Events.MovementDeletedEvent 0 { movementId = movementId }

        updatedExpenses =
            List.map
                (\expense ->
                    if expense.id == movementId then
                        { expense | deletedAt = Just "deleted" }

                    else
                        expense
                )
                model.expenses

        baseModel =
            { model
                | events = event :: model.events
                , expenses = Model.activeExpenses updatedExpenses
            }
    in
    ( if isTutorialDelete then
        { baseModel | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialExpenseId = Nothing }

      else
        baseModel
    , Cmd.batch
        [ config.appendEvent model.currentLedgerId event
        , if isTutorialDelete then
            config.completeTutorial

          else
            Cmd.none
        ]
    )


edit : String -> Model -> ( Model, Cmd msg )
edit expenseId model =
    case List.head (List.filter (\expense -> expense.id == expenseId) model.expenses) of
        Just expense ->
            ( { model
                | form = Accounting.expenseToForm expense model.form
                , error = ""
              }
            , Cmd.none
            )

        Nothing ->
            ( { model | error = "No se encontró el gasto a editar" }, Cmd.none )


cancelEdit : Model -> ( Model, Cmd msg )
cancelEdit model =
    ( { model
        | form = Accounting.emptyForm
        , error = ""
      }
        |> Model.ensureSelectedAccount
    , Cmd.none
    )


handleEventsLoaded : Decode.Value -> Model -> ( Model, Cmd msg )
handleEventsLoaded value model =
    case Decode.decodeValue (Decode.list Events.eventDecoder) value of
        Ok events ->
            let
                projectedExpenses =
                    Projector.projectEvents events
            in
            ( { model
                | events = events
                , expenses = Model.activeExpenses projectedExpenses
              }
            , Cmd.none
            )

        Err error ->
            ( { model | error = Decode.errorToString error }, Cmd.none )
