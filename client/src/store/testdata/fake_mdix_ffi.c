// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "fake_mdix_ffi.c"
// ============================================================================

// A stand-in for DixScript's C library, just big enough for the store tests to
// run without it. It understands documents of the form
// `@DATA( key = 5, name = "text" )` and writes the same form back.
// Build:  cc -shared -fPIC -o libfake_mdix.so client/src/store/testdata/fake_mdix_ffi.c

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ENTRIES 32

typedef struct {
    char key[48];
    char text[96];
    int number;
    bool is_text;
} Entry;

typedef struct {
    Entry entries[MAX_ENTRIES];
    int count;
} Doc;

static char last_error_text[96] = "";

const char *mdix_version(void) { return "fake-1.0"; }

const char *mdix_get_last_error(void) { return last_error_text; }

static Entry *find(Doc *doc, const char *key)
{
    for (int i = 0; i < doc->count; i++) {
        if (strcmp(doc->entries[i].key, key) == 0) return &doc->entries[i];
    }
    return NULL;
}

static Entry *add(Doc *doc, const char *key)
{
    Entry *entry = find(doc, key);
    if (entry) return entry;
    if (doc->count == MAX_ENTRIES) return NULL;
    entry = &doc->entries[doc->count++];
    memset(entry, 0, sizeof *entry);
    snprintf(entry->key, sizeof entry->key, "%s", key);
    return entry;
}

void *mdix_load_str(const char *source)
{
    const char *p = strstr(source, "@DATA(");
    if (!p) {
        snprintf(last_error_text, sizeof last_error_text, "no @DATA block");
        return NULL;
    }
    p += 6;
    Doc *doc = calloc(1, sizeof *doc);
    for (;;) {
        while (*p == ' ' || *p == ',' || *p == '\n' || *p == '\r' || *p == '\t') p++;
        if (*p == ')') return doc;
        if (*p == '\0') break;
        char key[48];
        int k = 0;
        while ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_') {
            if (k < 47) key[k++] = *p;
            p++;
        }
        key[k] = '\0';
        while (*p == ' ') p++;
        if (k == 0 || *p != '=') break;
        p++;
        while (*p == ' ') p++;
        Entry *entry = add(doc, key);
        if (!entry) break;
        if (*p == '"') {
            p++;
            int t = 0;
            while (*p && *p != '"') {
                if (t < 95) entry->text[t++] = *p;
                p++;
            }
            if (*p != '"') break;
            p++;
            entry->is_text = true;
        } else {
            entry->number = atoi(p);
            while (*p && *p != ',' && *p != ' ' && *p != ')') p++;
        }
    }
    free(doc);
    snprintf(last_error_text, sizeof last_error_text, "could not parse the document");
    return NULL;
}

void mdix_free(void *db) { free(db); }

bool mdix_exists(void *db, const char *path) { return find((Doc *)db, path) != NULL; }

int mdix_get_int(void *db, const char *path)
{
    Entry *entry = find((Doc *)db, path);
    return entry ? entry->number : 0;
}

char *mdix_get_string(void *db, const char *path)
{
    Entry *entry = find((Doc *)db, path);
    if (!entry || !entry->is_text) return NULL;
    return strdup(entry->text);
}

void mdix_free_string(char *text) { free(text); }

void *mdix_builder_new(void) { return calloc(1, sizeof(Doc)); }

void mdix_builder_free(void *builder) { free(builder); }

bool mdix_builder_set_int(void *builder, const char *path, int value)
{
    Entry *entry = add((Doc *)builder, path);
    if (!entry) return false;
    entry->number = value;
    entry->is_text = false;
    return true;
}

bool mdix_builder_set_string(void *builder, const char *path, const char *value)
{
    Entry *entry = add((Doc *)builder, path);
    if (!entry) return false;
    snprintf(entry->text, sizeof entry->text, "%s", value);
    entry->is_text = true;
    return true;
}

char *mdix_builder_to_string(void *builder)
{
    Doc *doc = (Doc *)builder;
    char *out = calloc(1, 4096);
    strcat(out, "@DATA(\n");
    for (int i = 0; i < doc->count; i++) {
        char line[200];
        if (doc->entries[i].is_text) snprintf(line, sizeof line, "    %s = \"%s\",\n", doc->entries[i].key, doc->entries[i].text);
        else snprintf(line, sizeof line, "    %s = %d,\n", doc->entries[i].key, doc->entries[i].number);
        strcat(out, line);
    }
    strcat(out, ")\n");
    return out;
}
