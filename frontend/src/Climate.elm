module Climate exposing (main)

{-| Terrain editor — a companion page to the map editor.

Full CRUD over terrain types and their universal properties. Because the
static dev server is read-only, "save" downloads a regenerated climate.toml the
author drops into data/ (server-side save is a later phase). The map editor
picks up the change on the next `just editor`.

-}

import Browser
import Char
import Dict exposing (Dict)
import File.Download as Download
import Html exposing (Html, button, div, input, option, select, span, text)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as D



-- MODEL


type alias Terrain =
    { id : String
    , key : String
    , glyph : String
    , color : String
    , props : Dict String String
    }


type alias Model =
    { terrains : List Terrain
    , propertyKeys : List String
    , selected : Int
    , newProp : String
    , status : String
    , pickerOpen : Bool
    , codepoint : String
    }


colorNames : List String
colorNames =
    [ "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_white" ]


terrainDecoder : D.Decoder Terrain
terrainDecoder =
    D.map5 Terrain
        (D.field "id" D.string)
        (D.field "key" D.string)
        (D.field "glyph" D.string)
        (D.field "color" D.string)
        (D.oneOf [ D.field "props" (D.dict D.string), D.succeed Dict.empty ])


paletteDecoder : D.Decoder ( List String, List Terrain )
paletteDecoder =
    D.map2 Tuple.pair
        (D.oneOf [ D.field "property_keys" (D.list D.string), D.succeed [] ])
        (D.field "climate" (D.list terrainDecoder))


init : () -> ( Model, Cmd Msg )
init _ =
    ( { terrains = [], propertyKeys = [], selected = 0, newProp = "", status = "loading palette…", pickerOpen = False, codepoint = "" }
    , Http.get { url = "climate.json", expect = Http.expectJson GotPalette paletteDecoder }
    )



-- UPDATE


type Msg
    = GotPalette (Result Http.Error ( List String, List Terrain ))
    | Select Int
    | AddTerrain
    | DeleteTerrain
    | SetId String
    | SetKey String
    | SetGlyph String
    | SetColor String
    | SetProp String String
    | NewPropInput String
    | AddProp
    | RemoveProp String
    | Save
    | TogglePicker
    | CodepointInput String
    | ApplyCodepoint


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPalette (Ok ( keys, terrains )) ->
            ( { model | propertyKeys = keys, terrains = terrains, status = "ready" }, Cmd.none )

        GotPalette (Err _) ->
            ( { model | status = "could not load climate.json" }, Cmd.none )

        Select i ->
            ( { model | selected = i }, Cmd.none )

        AddTerrain ->
            let
                used =
                    List.map .key model.terrains

                key =
                    freeKey used

                terrain =
                    { id = "new_climate", key = key, glyph = "?", color = "white", props = Dict.empty }
            in
            ( { model | terrains = model.terrains ++ [ terrain ], selected = List.length model.terrains, status = "added climate" }, Cmd.none )

        DeleteTerrain ->
            ( { model
                | terrains = List.indexedMap Tuple.pair model.terrains |> List.filter (\( i, _ ) -> i /= model.selected) |> List.map Tuple.second
                , selected = max 0 (model.selected - 1)
                , status = "deleted climate"
              }
            , Cmd.none
            )

        SetId v ->
            ( updateSelected (\t -> { t | id = v }) model, Cmd.none )

        SetKey v ->
            ( updateSelected (\t -> { t | key = String.left 1 v }) model, Cmd.none )

        SetGlyph v ->
            ( updateSelected (\t -> { t | glyph = v }) model, Cmd.none )

        SetColor v ->
            ( updateSelected (\t -> { t | color = v }) model, Cmd.none )

        SetProp k v ->
            ( updateSelected
                (\t ->
                    { t
                        | props =
                            if String.isEmpty (String.trim v) then
                                Dict.remove k t.props

                            else
                                Dict.insert k v t.props
                    }
                )
                model
            , Cmd.none
            )

        NewPropInput v ->
            ( { model | newProp = v }, Cmd.none )

        AddProp ->
            let
                k =
                    String.trim model.newProp
            in
            if String.isEmpty k || List.member k model.propertyKeys then
                ( { model | newProp = "" }, Cmd.none )

            else
                ( { model | propertyKeys = model.propertyKeys ++ [ k ], newProp = "", status = "added property " ++ k }, Cmd.none )

        RemoveProp k ->
            ( { model
                | propertyKeys = List.filter (\p -> p /= k) model.propertyKeys
                , terrains = List.map (\t -> { t | props = Dict.remove k t.props }) model.terrains
                , status = "removed property " ++ k
              }
            , Cmd.none
            )

        Save ->
            ( { model | status = "saved climate.toml — drop it in data/ and re-run just editor" }
            , Download.string "climate.toml" "application/toml" (toToml model)
            )

        TogglePicker ->
            ( { model | pickerOpen = not model.pickerOpen }, Cmd.none )

        CodepointInput v ->
            ( { model | codepoint = v }, Cmd.none )

        ApplyCodepoint ->
            case parseCodepoint model.codepoint of
                Just code ->
                    ( updateSelected (\t -> { t | glyph = String.fromChar (Char.fromCode code) }) model
                    , Cmd.none
                    )

                Nothing ->
                    ( { model | status = "not a valid hex codepoint" }, Cmd.none )


updateSelected : (Terrain -> Terrain) -> Model -> Model
updateSelected f model =
    { model | terrains = List.indexedMap (\i t -> ifEqual i model.selected (f t) t) model.terrains }


ifEqual : Int -> Int -> a -> a -> a
ifEqual a b yes no =
    if a == b then
        yes

    else
        no


freeKey : List String -> String
freeKey used =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        |> String.toList
        |> List.map String.fromChar
        |> List.filter (\c -> not (List.member c used))
        |> List.head
        |> Maybe.withDefault "?"


parseCodepoint : String -> Maybe Int
parseCodepoint raw =
    raw |> String.trim |> String.toUpper |> stripPrefix "U+" |> stripPrefix "0X" |> hexToInt


stripPrefix : String -> String -> String
stripPrefix prefix s =
    if String.startsWith prefix s then
        String.dropLeft (String.length prefix) s

    else
        s


hexToInt : String -> Maybe Int
hexToInt s =
    if String.isEmpty s then
        Nothing

    else
        String.foldl (\c acc -> Maybe.map2 (\n d -> n * 16 + d) acc (hexDigit c)) (Just 0) s


hexDigit : Char -> Maybe Int
hexDigit c =
    let
        n =
            Char.toCode c
    in
    if n >= 48 && n <= 57 then
        Just (n - 48)

    else if n >= 65 && n <= 70 then
        Just (n - 55)

    else
        Nothing



-- TOML EXPORT


toToml : Model -> String
toToml model =
    let
        keysLine =
            "property_keys = [" ++ (model.propertyKeys |> List.map tomlString |> String.join ", ") ++ "]\n\n"
    in
    keysLine ++ (model.terrains |> List.map terrainToToml |> String.join "\n")


terrainToToml : Terrain -> String
terrainToToml t =
    "[[climate]]\n"
        ++ ("id = " ++ tomlString t.id ++ "\n")
        ++ ("key = " ++ tomlString t.key ++ "\n")
        ++ ("glyph = " ++ tomlString t.glyph ++ "\n")
        ++ ("color = " ++ tomlString t.color ++ "\n")
        ++ (if Dict.isEmpty t.props then
                ""

            else
                "props = { " ++ (t.props |> Dict.toList |> List.map (\( k, v ) -> k ++ " = " ++ tomlString v) |> String.join ", ") ++ " }\n"
           )


tomlString : String -> String
tomlString s =
    "\"" ++ (s |> String.replace "\\" "\\\\" |> String.replace "\"" "\\\"") ++ "\""



-- VIEW


view : Model -> Html Msg
view model =
    div [ A.style "font-family" "monospace", A.style "background" "#0f1115", A.style "color" "#ddd", A.style "min-height" "100vh", A.style "padding" "12px" ]
        [ div [ A.style "font-size" "18px", A.style "margin-bottom" "8px" ] [ text "climate editor" ]
        , div [ A.style "display" "flex", A.style "gap" "24px", A.style "flex-wrap" "wrap", A.style "align-items" "flex-start" ]
            [ listView model
            , detailView model
            , propsView model
            ]
        , div [ A.style "margin-top" "12px" ] [ plainButton Save "save climate.toml" ]
        , div [ A.style "margin-top" "8px", A.style "opacity" "0.85" ] [ text model.status ]
        ]


listView : Model -> Html Msg
listView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "climate" ]
        , div [] (List.indexedMap (terrainRow model) model.terrains)
        , div [ A.style "margin-top" "6px" ] [ plainButton AddTerrain "+ add climate" ]
        ]


terrainRow : Model -> Int -> Terrain -> Html Msg
terrainRow model i t =
    div
        [ onClick (Select i)
        , A.style "cursor" "pointer"
        , A.style "padding" "2px 6px"
        , A.style "background"
            (if i == model.selected then
                "#2b3550"

             else
                "transparent"
            )
        ]
        [ span [ A.style "color" (cssColor t.color) ] [ text t.glyph ]
        , text (" " ++ t.id)
        ]


detailView : Model -> Html Msg
detailView model =
    case selectedTerrain model of
        Nothing ->
            div [ A.style "opacity" "0.6" ] [ text "no climate selected" ]

        Just t ->
            div [ A.style "min-width" "260px" ]
                [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "edit climate" ]
                , field "id" (textInput t.id SetId)
                , field "key" (textInput t.key SetKey)
                , glyphSection model t
                , field "color" (colorSelect t.color)
                , div [ A.style "margin" "6px 0" ]
                    [ text "preview: "
                    , span [ A.style "color" (cssColor t.color), A.style "font-size" "18px" ] [ text t.glyph ]
                    ]
                , div [ A.style "margin-top" "6px", A.style "opacity" "0.7" ] [ text "property values" ]
                , div [] (List.map (propValueRow t) model.propertyKeys)
                , div [ A.style "margin-top" "8px" ] [ plainButton DeleteTerrain "delete this climate" ]
                ]


propValueRow : Terrain -> String -> Html Msg
propValueRow t key =
    field key (textInput (Dict.get key t.props |> Maybe.withDefault "") (SetProp key))


propsView : Model -> Html Msg
propsView model =
    div [ A.style "min-width" "220px" ]
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "universal properties" ]
        , div [] (List.map propKeyRow model.propertyKeys)
        , div [ A.style "margin-top" "6px", A.style "display" "flex", A.style "gap" "4px" ]
            [ textInput model.newProp NewPropInput
            , plainButton AddProp "+ add"
            ]
        , div [ A.style "margin-top" "8px", A.style "opacity" "0.55", A.style "max-width" "220px", A.style "font-size" "12px" ]
            [ text "Adding a property gives it to every climate as null until you set a value." ]
        ]


propKeyRow : String -> Html Msg
propKeyRow key =
    div [ A.style "display" "flex", A.style "gap" "6px", A.style "align-items" "center" ]
        [ text key
        , button [ onClick (RemoveProp key), A.style "background" "#1a1d24", A.style "color" "#d88", A.style "border" "1px solid #333", A.style "cursor" "pointer" ] [ text "×" ]
        ]


glyphSection : Model -> Terrain -> Html Msg
glyphSection model t =
    div []
        [ field "glyph"
            (div [ A.style "display" "flex", A.style "gap" "6px", A.style "align-items" "center" ]
                [ textInput t.glyph SetGlyph
                , plainButton TogglePicker
                    (if model.pickerOpen then
                        "close"

                     else
                        "pick…"
                    )
                ]
            )
        , if model.pickerOpen then
            div [ A.style "margin" "4px 0 4px 98px" ]
                [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "characters (click to set)" ]
                , asciiTable
                , div [ A.style "margin-top" "8px", A.style "display" "flex", A.style "gap" "6px", A.style "align-items" "center" ]
                    [ span [ A.style "opacity" "0.8" ] [ text "unicode U+" ]
                    , textInput model.codepoint CodepointInput
                    , plainButton ApplyCodepoint "set"
                    ]
                ]

          else
            text ""
        ]


glyphRanges : List ( String, Int, Int )
glyphRanges =
    [ ( "ASCII", 32, 126 )
    , ( "Latin-1", 160, 255 )
    , ( "Box drawing", 0x2500, 0x257F )
    , ( "Block elements", 0x2580, 0x259F )
    , ( "Geometric shapes", 0x25A0, 0x25FF )
    , ( "Arrows", 0x2190, 0x21FF )
    ]


asciiTable : Html Msg
asciiTable =
    div
        [ A.style "max-height" "320px"
        , A.style "overflow-y" "auto"
        , A.style "max-width" "380px"
        , A.style "border" "1px solid #222"
        , A.style "padding" "4px"
        ]
        (List.map glyphRangeView glyphRanges)


glyphRangeView : ( String, Int, Int ) -> Html Msg
glyphRangeView ( label, start, end ) =
    div [ A.style "margin-bottom" "6px" ]
        [ div [ A.style "opacity" "0.55", A.style "font-size" "11px", A.style "margin-bottom" "2px" ] [ text label ]
        , div [ A.style "display" "flex", A.style "flex-wrap" "wrap", A.style "gap" "2px" ]
            (List.range start end |> List.map asciiCell)
        ]


asciiCell : Int -> Html Msg
asciiCell code =
    let
        ch =
            String.fromChar (Char.fromCode code)
    in
    button
        [ onClick (SetGlyph ch)
        , A.title (String.fromInt code)
        , A.style "width" "20px"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "cursor" "pointer"
        , A.style "font-family" "monospace"
        ]
        [ text ch ]


field : String -> Html Msg -> Html Msg
field label control =
    div [ A.style "display" "flex", A.style "gap" "8px", A.style "align-items" "center", A.style "margin" "2px 0" ]
        [ span [ A.style "display" "inline-block", A.style "width" "90px", A.style "opacity" "0.8" ] [ text label ]
        , control
        ]


textInput : String -> (String -> Msg) -> Html Msg
textInput val toMsg =
    input [ A.value val, onInput toMsg, A.style "background" "#1a1d24", A.style "color" "#ddd", A.style "border" "1px solid #333", A.style "padding" "2px 4px" ] []


colorSelect : String -> Html Msg
colorSelect current =
    select [ onInput SetColor, A.value current, A.style "background" "#1a1d24", A.style "color" "#ddd", A.style "border" "1px solid #333" ]
        (List.map (\c -> option [ A.value c, A.selected (c == current) ] [ text c ]) colorNames)


plainButton : Msg -> String -> Html Msg
plainButton msg label =
    button [ onClick msg, A.style "background" "#1a1d24", A.style "color" "#ddd", A.style "border" "1px solid #333", A.style "padding" "4px 8px", A.style "cursor" "pointer" ] [ text label ]


selectedTerrain : Model -> Maybe Terrain
selectedTerrain model =
    model.terrains |> List.drop model.selected |> List.head


cssColor : String -> String
cssColor name =
    case name of
        "black" ->
            "#1b1b1b"

        "red" ->
            "#d35f5f"

        "green" ->
            "#3c9a4e"

        "yellow" ->
            "#c9b458"

        "blue" ->
            "#3a78c2"

        "magenta" ->
            "#b05fb0"

        "cyan" ->
            "#4dd0e1"

        "white" ->
            "#cfcfcf"

        "bright_black" ->
            "#7a7a7a"

        "bright_red" ->
            "#ff6b6b"

        "bright_green" ->
            "#8bc34a"

        "bright_yellow" ->
            "#e6c84f"

        "bright_blue" ->
            "#5b9be0"

        "bright_magenta" ->
            "#e07be0"

        "bright_cyan" ->
            "#7fe7f3"

        "bright_white" ->
            "#ffffff"

        _ ->
            "#aaaaaa"



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
