#!/bin/bash
#=======================================================================
# SLURM - Table2Image (T2I) on ALL Tabular Datasets
#=======================================================================
#SBATCH --account=def-arashmoh
#SBATCH --job-name=T2I_All_Datasets
#SBATCH --nodes=1
#SBATCH --gpus-per-node=h100:1
#SBATCH --cpus-per-task=10
#SBATCH --mem=80G
#SBATCH --time=72:00:00
#=======================================================================
#SBATCH --output=/home/gkianfar/scratch/Amin/T2I/outputs/logs/t2i_%A.out
#SBATCH --error=/home/gkianfar/scratch/Amin/T2I/outputs/logs/t2i_%A.err
#=======================================================================

BASE_T2I="/home/gkianfar/scratch/Amin/T2I"
BASE_TAB2VIS="/home/gkianfar/scratch/Amin/Tab2Vis"

DATASETS_DIR="$BASE_TAB2VIS/Unzippeddata/CSV"
OUTPUTS_DIR="$BASE_T2I/outputs"
LOGS_DIR="$OUTPUTS_DIR/logs"
RESULTS_DIR="$OUTPUTS_DIR/resualt"

MAIN_SCRIPT="$BASE_T2I/V2I/main.py"
VENV_PATH="$BASE_TAB2VIS/venvMsc/bin/activate"

TIMEOUT_PER_DATASET=21600                # 6 hours per dataset

echo "=========================================================="
echo "  TABLE2IMAGE - Full Dataset Run"
echo "=========================================================="
echo "  Job ID   : $SLURM_JOB_ID"
echo "  Node     : $SLURMD_NODENAME"
echo "  Started  : $(date)"
echo "  Datasets : $DATASETS_DIR"
echo "  Results  : $RESULTS_DIR"
echo "  Timeout  : ${TIMEOUT_PER_DATASET}s per dataset"
echo "=========================================================="

# Setup directories
mkdir -p "$LOGS_DIR"
mkdir -p "$RESULTS_DIR"

# Dataset check
if [ ! -d "$DATASETS_DIR" ]; then
    echo "❌ Dataset directory not found: $DATASETS_DIR"
    exit 1
fi

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "❌ main.py not found: $MAIN_SCRIPT"
    exit 1
fi

# Modules + env
module purge
module load StdEnv/2023
module load python/3.11
module load cuda/12.2

source "$VENV_PATH"

echo "Python version:"
python --version

DATASET_COUNT=$(find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "✅ Found $DATASET_COUNT dataset folders"

#=======================================================================
# Tracking counters
#=======================================================================
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_LIST=()

#=======================================================================
# Main loop
#=======================================================================
echo "🚀 Starting full training on all datasets..."

for DATASET_DIR in $(find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 -type d | sort); do

    DATASET_NAME=$(basename "$DATASET_DIR")
    DATA_FILE=$(find "$DATASET_DIR" -maxdepth 1 -type f \( -iname "*.csv" -o -iname "*.arff" -o -iname "*.data" \) | head -n 1)

    if [ -z "$DATA_FILE" ]; then
        echo "⚠️  [$DATASET_NAME] No data file found — skipping"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "----------------------------------------------------------"
    echo "▶  Dataset : $DATASET_NAME"
    echo "   File    : $DATA_FILE"
    echo "   Time    : $(date)"
    echo "----------------------------------------------------------"

    timeout "$TIMEOUT_PER_DATASET" python "$MAIN_SCRIPT" \
        --data        "$DATA_FILE"   \
        --interp_root "$RESULTS_DIR" \
        --num_images  20

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "   ✅ Done  (exit 0)"
        SUCCESS=$((SUCCESS + 1))
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "   ⏰ TIMEOUT after ${TIMEOUT_PER_DATASET}s"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$DATASET_NAME (timeout)")
    else
        echo "   ❌ FAILED (exit $EXIT_CODE)"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$DATASET_NAME (exit $EXIT_CODE)")
    fi

done

#=======================================================================
# Final Summary
#=======================================================================
echo ""
echo "=========================================================="
echo "  FINAL SUMMARY"
echo "=========================================================="
echo "  Total datasets : $((SUCCESS + FAILED + SKIPPED))"
echo "  ✅ Succeeded   : $SUCCESS"
echo "  ❌ Failed      : $FAILED"
echo "  ⚠️  Skipped    : $SKIPPED"
echo "  Finished       : $(date)"
echo "=========================================================="

if [ ${#FAILED_LIST[@]} -gt 0 ]; then
    echo ""
    echo "  Failed datasets:"
    for ITEM in "${FAILED_LIST[@]}"; do
        echo "    - $ITEM"
    done
fi

echo ""
echo "  Results : $RESULTS_DIR/"
echo "=========================================================="

[ $FAILED -eq 0 ] && exit 0 || exit 1
