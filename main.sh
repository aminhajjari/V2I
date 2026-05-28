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

# ── Paths ──────────────────────────────────────────────────────────────
BASE_TAB2VIS="/home/gkianfar/scratch/Amin/Tab2Vis"
BASE_T2I="/home/gkianfar/scratch/Amin/T2I"

DATASETS_DIR="$BASE_TAB2VIS/Unzippeddata/CSV"
DATASET_ROOT="$BASE_TAB2VIS/datasets"          # MNIST / FashionMNIST root expected by main.py

OUTPUTS_DIR="$BASE_T2I/outputs"
LOGS_DIR="$OUTPUTS_DIR/logs"
RESULTS_DIR="$OUTPUTS_DIR/resualt"             # matches your existing folder name

MAIN_SCRIPT="$BASE_T2I/V2I/main.py"
VENV_PATH="$BASE_TAB2VIS/venvMsc/bin/activate"

TIMEOUT_PER_DATASET=21600                       # 6 hours per dataset (seconds)

# ── Setup ──────────────────────────────────────────────────────────────
mkdir -p "$LOGS_DIR"
mkdir -p "$RESULTS_DIR"

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

# ── Environment ────────────────────────────────────────────────────────
module purge
module load StdEnv/2023
module load python/3.11
module load cuda/12.2

source "$VENV_PATH"

echo ""
echo "Python : $(python --version)"
echo "Which  : $(which python)"
echo ""

# ── Sanity checks ──────────────────────────────────────────────────────
if [ ! -d "$DATASETS_DIR" ]; then
    echo "❌ Dataset directory not found: $DATASETS_DIR"
    exit 1
fi

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "❌ main.py not found: $MAIN_SCRIPT"
    exit 1
fi

DATASET_FOLDERS=($(find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 -type d | sort))
TOTAL=${#DATASET_FOLDERS[@]}
echo "✅ Found $TOTAL dataset folders"
echo ""

# ── Tracking counters ──────────────────────────────────────────────────
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_LIST=()

# ── Main loop ──────────────────────────────────────────────────────────
for DATASET_DIR in "${DATASET_FOLDERS[@]}"; do

    DATASET_NAME=$(basename "$DATASET_DIR")

    # Locate the data file inside the folder (csv / arff / data)
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

    # Per-dataset log files (inside LOGS_DIR)
    DS_LOG="$LOGS_DIR/${DATASET_NAME}.log"

    timeout "$TIMEOUT_PER_DATASET" python "$MAIN_SCRIPT" \
        --data        "$DATA_FILE"   \
        --interp_root "$RESULTS_DIR" \
        --num_images  20             \
        

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "   ✅ Done  (exit 0)"
        SUCCESS=$((SUCCESS + 1))
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "   ⏰ TIMEOUT after ${TIMEOUT_PER_DATASET}s"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$DATASET_NAME (timeout)")
    else
        echo "   ❌ FAILED (exit $EXIT_CODE) — see $DS_LOG"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$DATASET_NAME (exit $EXIT_CODE)")
    fi

done

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=========================================================="
echo "  FINAL SUMMARY"
echo "=========================================================="
echo "  Total datasets : $TOTAL"
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
echo "  Per-dataset logs : $LOGS_DIR/"
echo "  Results / plots  : $RESULTS_DIR/"
echo "=========================================================="

[ $FAILED -eq 0 ] && exit 0 || exit 1
