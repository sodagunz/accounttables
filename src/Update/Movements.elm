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
import InvoiceAllocation
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
            case validateMovementForSave readyModel movement of
                Ok () ->
                    persistMovement config readyModel (prepareMovementForSave readyModel movement)

                Err error ->
                    ( { readyModel | error = error }, Cmd.none )

        Err error ->
            ( { readyModel | error = error }, Cmd.none )


validateMovementForSave : Model -> Accounting.Movement -> Result String ()
validateMovementForSave model movement =
    if model.form.editingId == Nothing && movement.movementType == Accounting.SupplierCreditNoteMovement then
        validateCreditNoteTargets model movement

    else
        Ok ()


validateCreditNoteTargets : Model -> Accounting.Movement -> Result String ()
validateCreditNoteTargets model creditNote =
    let
        eligibleTargetIds : List String
        eligibleTargetIds =
            Model.activeMovements model.expenses
                |> List.filter (eligibleCreditNoteTarget creditNote)
                |> List.map .id
    in
    if List.isEmpty eligibleTargetIds then
        Err "No hay facturas de esta cuenta y divisa para compensar con la nota de crédito. Crea o importa la factura primero."

    else if targetIdsFor creditNote |> List.any (\targetId -> List.member targetId eligibleTargetIds) then
        Ok ()

    else
        Err "Selecciona al menos una factura de esta cuenta y divisa para compensar la nota de crédito."


eligibleCreditNoteTarget : Accounting.Movement -> Accounting.Movement -> Bool
eligibleCreditNoteTarget creditNote target =
    target.deletedAt
        == Nothing
        && target.accountId
        == creditNote.accountId
        && target.movementType
        == Accounting.SupplierInvoiceMovement
        && target.inputCurrency
        == creditNote.inputCurrency


prepareMovementForSave : Model -> Accounting.Movement -> Accounting.Movement
prepareMovementForSave model movement =
    movement
        |> resolveAutoAllocation model
        |> withGeneratedRelatedDescription model


resolveAutoAllocation : Model -> Accounting.Movement -> Accounting.Movement
resolveAutoAllocation model movement =
    if model.form.editingId == Nothing && movement.relatedToInvoice && movement.allocationIntent == Nothing then
        { movement | allocationIntent = InvoiceAllocation.resolveAutoTargets (Model.activeMovements model.expenses) movement }

    else
        movement


withGeneratedRelatedDescription : Model -> Accounting.Movement -> Accounting.Movement
withGeneratedRelatedDescription model movement =
    if movement.relatedToInvoice then
        case movement.movementType of
            Accounting.ExpenseMovement ->
                { movement | description = Just (generatedExpenseDescription (targetDocuments model movement)) }

            Accounting.IncomeMovement ->
                { movement | description = Just (generatedIncomeDescription (targetDocuments model movement)) }

            _ ->
                movement

    else
        movement


targetDocuments : Model -> Accounting.Movement -> List Accounting.Movement
targetDocuments model movement =
    targetIdsFor movement
        |> List.filterMap (findMovementById (Model.activeMovements model.expenses))


targetIdsFor : Accounting.Movement -> List String
targetIdsFor movement =
    movement.allocationIntent
        |> Maybe.map .targetIds
        |> Maybe.withDefault []


findMovementById : List Accounting.Movement -> String -> Maybe Accounting.Movement
findMovementById movements movementId =
    movements
        |> List.filter (\movement -> movement.id == movementId)
        |> List.head


generatedExpenseDescription : List Accounting.Movement -> String
generatedExpenseDescription documents =
    generatedDescription
        { singular = "Pago factura"
        , plural = "Pago facturas"
        , fallback = "Pago facturas"
        }
        documents


generatedIncomeDescription : List Accounting.Movement -> String
generatedIncomeDescription documents =
    generatedDescription
        { singular = "Cobro nota de crédito"
        , plural = "Cobro notas de crédito"
        , fallback = "Cobro notas"
        }
        documents


generatedDescription : { singular : String, plural : String, fallback : String } -> List Accounting.Movement -> String
generatedDescription labels documents =
    let
        numbers : List String
        numbers =
            documents
                |> List.filterMap .documentNumber
                |> List.map String.trim
                |> List.filter ((/=) "")
    in
    case ( documents, numbers ) of
        ( [ _ ], [ number ] ) ->
            labels.singular ++ " " ++ number

        ( _ :: _ :: _, _ :: _ ) ->
            labels.plural ++ " " ++ String.join ", " numbers

        _ ->
            labels.fallback


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
                                , relatedToInvoice = movement.relatedToInvoice
                                , documentNumber = movement.documentNumber
                                , allocationIntent = movement.allocationIntent
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
                                , relatedToInvoice = movement.relatedToInvoice
                                , documentNumber = movement.documentNumber
                                , allocationIntent = movement.allocationIntent
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
            , relatedToInvoice = False
            , documentNumber = ""
            , allocationIntent = Nothing
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
