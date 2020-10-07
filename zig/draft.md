```
// top-level global ranges over the whole game
global weapons[axe, sword];

// scopes limit definitions to local
scope beginning {
  // you can define rooms
  room kitchen {
    // introduce the room
    intro "the dark kitchen";

    // (items) in parens are hidden
    atoms apple, knife, key, key2, (phantom-key);

    // you can change how an atom is displayed on the screen by giving it a
    // different name
    display key2 as key;

    // and give long names with spaces
    display knife as "butcher's knife";

    // visible rule which requires one key
    "unlock chest" [key]         -> (phantom-key);

    // intros can be bound to requirements
    [(phantom-key)] intro "hidden paths opened";

    // hidden goal only visible with the satisfied requirement
    [(phantom-key)] "take sword" -> weapons.sword;

    // it's possible to mix hidden and visible
    [(phantom-key)] "take axe" [key] -> weapons.axe;

    // special functions use #
    "go back" -> #back;

    "check the stove" -> key;
    "check the cup on the table" -> key2;

    "go to hallway" [key, key2] -> @hallway;
  }

  room hallway {
    // you can die
    "die" -> #die;

    "flip switch" -> off;

    // rules can consume items
    {off} "flip switch";

    // always matches the first rule
    [off] "touch wire" -> say "lucky the wire wasn't live";
    "touch wire" -> #die;
  }
}
```
