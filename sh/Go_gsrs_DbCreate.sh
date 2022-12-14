#!/bin/bash
#############################################################################
#
set -e
#
T0=$(date +%s)
#
cwd=$(pwd)
#
DBNAME="gsrs"
#
DBDIR=$(cd $HOME/../data/GSRS/data; pwd)
#
if [ ! -e "${DBDIR}" ]; then
	printf "ERROR: DBDIR not found: ${DBDIR}\n"
	exit 1
fi
#
#
tsvfiles="\
$DBDIR/UNII_Data/UNII_Records_18Nov2022.txt \
$DBDIR/UNIIs/UNII_Names_18Nov2022.txt \
"
#
psql -c "DROP DATABASE IF EXISTS $DBNAME"
psql -c "CREATE DATABASE $DBNAME"
#
psql -d $DBNAME -c "COMMENT ON DATABASE $DBNAME IS 'GSRS: Global Substance Registration System'";
#
i_table="0"
for tsvfile in $tsvfiles ; do
	i_table=$[$i + 1]
	n_lines=$(cat $tsvfile |wc -l)
	tname=$(basename $tsvfile |perl -pe 's/^(.*)_\d.*$/$1/;'|perl -e 'print(lc(<STDIN>))')
	printf "${i_table}. CREATING AND LOADING TABLE: ${tname} FROM INPUT FILE: ${tsvfile} (${n_lines} lines)\n"
	#
	python3 -m BioClients.util.pandas.Csv2Sql create --fixtags --nullify --maxchar 2000 \
		--i $tsvfile --tsv --tablename "$tname" \
		|psql -d $DBNAME
	#
	python3 -m BioClients.util.pandas.Csv2Sql insert --fixtags --nullify --maxchar 2000 \
		--i $tsvfile --tsv --tablename "$tname" \
		|psql -q -d $DBNAME
	#
done
printf "TABLES CREATED AND LOADED: ${i_table}\n"
psql -d $DBNAME -c "UPDATE unii_records SET smiles = NULL WHERE smiles = ''";
#
sudo -u postgres psql -d $DBNAME -c "CREATE EXTENSION rdkit";
psql -d $DBNAME -c "ALTER TABLE unii_records ADD COLUMN cansmi VARCHAR(2000)";
psql -d $DBNAME -c "ALTER TABLE unii_records ADD COLUMN molecule MOL";
psql -d $DBNAME -c "UPDATE unii_records SET molecule = mol_from_smiles(smiles::cstring) WHERE smiles IS NOT NULL";
psql -d $DBNAME -c "UPDATE unii_records SET cansmi = mol_to_smiles(molecule) WHERE molecule IS NOT NULL"
psql -d $DBNAME -c "UPDATE unii_records SET cansmi = NULL WHERE cansmi = ''";
# Morgan (Circular) Fingerprints (with radius=2 ECFP-diameter=4-like).
psql -d $DBNAME -c "SET rdkit.morgan_fp_size=2048"
psql -d $DBNAME -c "ALTER TABLE unii_records DROP COLUMN IF EXISTS fp"
psql -d $DBNAME -c "ALTER TABLE unii_records ADD COLUMN fp BFP"
psql -d $DBNAME -c "UPDATE unii_records SET fp = morganbv_fp(molecule, 2)"
psql -d $DBNAME -c "CREATE INDEX fps_ecfp_idx ON unii_records USING gist(fp)"
###
#
###
# How to dump and restore:
# pg_dump --no-privileges -Fc -d ${DBNAME} >${DBNAME}.pgdump
# createdb ${DBNAME} ; pg_restore -e -O -x -d ${DBNAME} ${DBNAME}.pgdump
###
printf "Elapsed: %ds\n" "$[$(date +%s) - $T0]"
#
