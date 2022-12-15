#!/bin/bash
#############################################################################
#
#set -e
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
smifile="$DBDIR/UNII_Data/UNII_Records_18Nov2022.smiles"
#
N=$(cat $smifile |wc -l)
printf "N_smiles = ${N}\n"
#
psql -d $DBNAME -c "SET rdkit.morgan_fp_size=2048"
#
###
# Workaround due to RDKit bug:
# 41302. UNII: 9S1BC7865F; SMILES: "[Cl-].[Cl-].[Cl-].[Cl-].[Cl-].[Nd+5]"
# UPDATE unii_records SET cansmi = mol_to_smiles(molecule) WHERE unii = '9S1BC7865F'
# ERROR:  molFromPickle: invalid value in pickle
# 
# 83049. UNII: T86H76439H; SMILES: "[F-].[F-].[F-].[F-].[F-].[Nd+5]"
# UPDATE unii_records SET cansmi = mol_to_smiles(molecule) WHERE unii = 'T86H76439H'
# ERROR:  molFromPickle: invalid value in pickle
###
# gsrs=> select mol_from_smiles('[Cl-].[Cl-].[Cl-].[Cl-].[Cl-].[Nd+5]') ;
# ERROR:  molFromPickle: invalid value in pickle
# gsrs=> select mol_from_smiles('[F-].[F-].[F-].[F-].[F-].[Nd+5]') ;
# ERROR:  molFromPickle: invalid value in pickle
###
problem_uniis="\
9S1BC7865F \
T86H76439H \
"
for unii in $problem_uniis ; do
	psql -e -d $DBNAME -c "UPDATE unii_records SET molecule = NULL WHERE unii = '${unii}'"
done
#
I=0
while [ $I -lt $N ]; do
	I=$[$I + 1]
	line=$(cat $smifile |sed -e "${I}q;d")
	smi=$(echo $line |awk '{print $1}')
	unii=$(echo $line |awk '{print $2}')
	printf "${I}. UNII: %s; SMILES: \"%s\"\n" "${unii}" "${smi}"
	psql -e -d $DBNAME -c "UPDATE unii_records SET cansmi = mol_to_smiles(molecule) WHERE unii = '${unii}'"
	psql -e -d $DBNAME -c "UPDATE unii_records SET fp = morganbv_fp(molecule, 2) WHERE unii = '${unii}'"
done
#

#
###
printf "Elapsed: %ds\n" "$[$(date +%s) - $T0]"
#
