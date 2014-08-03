#!/bin/bash

tmsu_db=~/.tmsu/default.db
dt_db=${XDG_CONFIG_HOME:-$HOME/.config}/darktable/library.db

function sql_tmsu () {
    echo -n "$@;" | sqlite3 $tmsu_db
}

function sql_dt () {
    echo -n "$@;" | sqlite3 $dt_db
}

function die_error () {
    echo "ERROR: $@" >&2
    exit 2
}

insert_maybe_get_id () {
    id=$(sql_dt "select id from tags where name='$1'")
    if [ -n "$id" ]; then
        echo $id
        return
    fi
    sql_dt "insert into tags (name) values ('$1'); select last_insert_rowid()"
}

tag_maybe () {
    local imgid=$1
    local tagid=$2
    sql_dt "insert or ignore into tagged_images values($imgid, $tagid)"
}

tmsu_hits=0
dt_hits=0

id_tag_imported_from_tmsu=$(insert_maybe_get_id imported-from-tmsu)

while IFS='|' read tag_id tag_name; do
    entries=$(sql_tmsu "select count(*) from file_tag where tag_id =$tag_id")
    echo "[$tag_id] $tag_name ($entries entries)";
    tag_id_dt=$(insert_maybe_get_id $tag_name)
    q="select id, directory, name from file as f join file_tag as ft where f.id = ft.file_id and ft.tag_id=$tag_id"
    while IFS='|' read id dir name; do
        tmsu_hits=$((tmsu_hits+1))
        echo "tmsu: $id, $dir and $name";
        q="select i.id from images as i
           join film_rolls as f on f.id = i.film_id
           and f.folder = '$dir' and i.filename = '$name'"
        # it's possible for there to be more than one result, if you duplicated an image for example
        matched=0
        while read id; do
            dt_hits=$((dt_hits+1))
            matched=$((matched+1))
            echo "dt equivalent #$matched: $id"
            tag_maybe $id $id_tag_imported_from_tmsu
            tag_maybe $id $tag_id_dt
        done < <(sql_dt "$q")
        [ $matched -gt 0 ] || die_error "no match found in darktable for image '$dir/$name'"
    done < <(sql_tmsu "$q")
done < <(sql_tmsu 'select * from tag')

echo "done!"
echo "total tmsu images processed: $tmsu_hits"
echo "total dt images updated: $dt_hits (can be more, if you duplicated images in DT, otherwise should be equal)"
