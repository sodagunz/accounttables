module Update.Movements exposing
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
        Ok movementId ->
            createOrUpdateMovement config movementId model

        Err error ->
            ( { model | error = Decode.errorToString error }, Cmd.none )


createOrUpdateMovement : Config msg -> String -> Model -> ( Model, Cmd msg )
createOrUpdateMovement config movementId model =
    let
        readyModel : Model
        readyModel =
            Model.ensureSelectedAccount model

        rate : Float
        rate =
            case readyModel.form.editingId of
                Just editingId ->
                    case List.head (List.filter (\movement -> movement.id == editingId) readyModel.expenses) of
                        Just movement ->
                            movement.exchangeRate

                        Nothing ->
                            readyModel.exchangeRate

                Nothing ->
                    readyModel.exchangeRate
    in
    case Accounting.buildMovement rate movementId (Model.activeAccounts readyModel) readyModel.form of
        Ok movement ->
            persistMovement config readyModel movement

        Err error ->
            ( { readyModel | error = error }, Cmd.none )


persistMovement : Config msg -> Model -> Accounting.Movement -> ( Model, Cmd msg )
persistMovement config readyModel movement =
    let
        eventAndUpdatedModel : ( Events.Event, Model )
        eventAndUpdatedModel =
            case readyModel.form.editingId of
                Just editingId ->
                    let
                        updateEvent : Events.Event
                        updateEvent =
                            Events.MovementUpdatedEvent 0
                                { movementId = editingId
                                , movementType = movement.movementType
                                , description = movement.description
                                , accountId = movement.accountId
                                , accountName = movement.accountName
                                , inputAmount = movement.inputAmount
                                , inputCurrency = movement.inputCurrency
                                , exchangeRate = movement.exchangeRate
                                , ars = movement.ars
                                , usd = movement.usd
                                , date = movement.date
                                }

                        updatedMovements : List Accounting.Movement
                        updatedMovements =
                            List.map
                                (\existing ->
                                    if existing.id == editingId then
                                        movement

                                    else
                                        existing
                                )
                                readyModel.expenses
                    in
                    ( updateEvent
                    , { readyModel
                        | events = updateEvent :: readyModel.events
                        , expenses = Model.activeMovements updatedMovements
                      }
                    )

                Nothing ->
                    let
                        createEvent : Events.Event
                        createEvent =
                            Events.MovementCreatedEvent 0
                                { id = movement.id
                                , movementType = movement.movementType
                                , description = movement.description
                                , accountId = movement.accountId
                                , accountName = movement.accountName
                                , inputAmount = movement.inputAmount
                                , inputCurrency = movement.inputCurrency
                                , exchangeRate = movement.exchangeRate
                                , ars = movement.ars
                                , usd = movement.usd
                                , date = movement.date
                                }
                    in
                    ( createEvent
                    , { readyModel
                        | events = createEvent :: readyModel.events
                        , expenses = movement :: Model.activeMovements readyModel.expenses
                      }
                    )

        event : Events.Event
        event =
            Tuple.first eventAndUpdatedModel

        updatedModel : Model
        updatedModel =
            Tuple.second eventAndUpdatedModel

        isNewMovement : Bool
        isNewMovement =
            readyModel.form.editingId == Nothing

        advanceResult : ( Model, Cmd msg )
        advanceResult =
            if isNewMovement then
                case updatedModel.tutorialState of
                    TutorialOpen FirstMovementStep ->
                        config.navigateTutorial DeleteMovementStep { updatedModel | tutorialMovementId = Just movement.id }

                    _ ->
                        ( updatedModel, Cmd.none )

            else
                ( updatedModel, Cmd.none )

        ( modelAfterAdvance, advanceCmd ) =
            advanceResult
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
        isTutorialDelete : Bool
        isTutorialDelete =
            case ( model.tutorialState, model.tutorialMovementId ) of
                ( TutorialOpen DeleteMovementStep, Just tutorialMovementId ) ->
                    tutorialMovementId == movementId

                _ ->
                    False

        event : Events.Event
        event =
            Events.MovementDeletedEvent 0 { movementId = movementId }

        updatedMovements : List Accounting.Movement
        updatedMovements =
            List.map
                (\movement ->
                    if movement.id == movementId then
                        { movement | deletedAt = Just "deleted" }

                    else
                        movement
                )
                model.expenses

        baseModel : Model
        baseModel =
            { model
                | events = event :: model.events
                , expenses = Model.activeMovements updatedMovements
            }
    in
    ( if isTutorialDelete then
        { baseModel | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialMovementId = Nothing }

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
edit movementId model =
    case List.head (List.filter (\movement -> movement.id == movementId) model.expenses) of
        Just movement ->
            ( { model
                | form = Accounting.movementToForm movement
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
                projectedMovements : List Accounting.Movement
                projectedMovements =
                    Projector.projectEvents events
            in
            ( { model
                | events = events
                , expenses = Model.activeMovements projectedMovements
              }
            , Cmd.none
            )

        Err error ->
            ( { model | error = Decode.errorToString error }, Cmd.none )
