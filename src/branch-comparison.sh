#!/bin/bash
#
# Branch Comparison Script
# ------------------------
# Determines if a current branch is up-to-date with (or ahead of) a target branch.
#
# Returns:
#   - Exit code 0 + "true" to stdout if branch is up-to-date or ahead
#   - Exit code 1 + "false" to stdout if branch is behind and needs updating
#   - Exit code 2+ for errors
#
# Note: All debug information is sent to stderr, only true/false to stdout

# Initialize result variables
RESULT="false"
REASON=""
IS_UP_TO_DATE=false
EXIT_CODE=0

# --- Argument validation ---
if [ "$#" -lt 2 ]; then
  echo "::error::Insufficient arguments provided" >&2
  echo "USAGE: $0 <current_branch> <target_branch>" >&2
  exit 2
fi

current_branch=$1
target_branch=$2

# --- Setup and validation ---
echo "::group::Branch Comparison Configuration" >&2
echo "Current branch: $current_branch" >&2
echo "Target branch: $target_branch" >&2
echo "::endgroup::" >&2

# Mark repository as safe
git config --global --add safe.directory "*" >&2

# Validate target branch exists
if ! git ls-remote --heads origin "$target_branch" | grep -q "$target_branch"; then
  echo "::error::Target branch '$target_branch' does not exist on remote" >&2
  echo "::set-output name=error::Target branch does not exist" >&2
  exit 3
fi

# Fetch latest branch information
echo "::group::Fetching branch information" >&2
git fetch --no-recurse-submodules origin "$target_branch" "$current_branch" >&2
echo "::endgroup::" >&2

# --- Branch comparison logic ---
echo "::group::Branch Comparison Analysis" >&2

# Case 1: Check if branches are identical (same commit)
current_sha=$(git rev-parse origin/"$current_branch")
target_sha=$(git rev-parse origin/"$target_branch")

if [ "$current_sha" = "$target_sha" ]; then
  RESULT="true"
  REASON="branches_identical"
  IS_UP_TO_DATE=true
  echo "RESULT: Branches are identical (pointing to the same commit)" >&2
  echo "::set-output name=is_up_to_date::true" >&2
  echo "::set-output name=reason::branches_identical" >&2
  echo "::notice::Branches are identical - no update needed" >&2
else
  # Find common ancestor for comparison
  merge_base=$(git merge-base origin/"$target_branch" origin/"$current_branch")
  echo "Common ancestor commit: $merge_base" >&2

  # Case 2: Check if target branch is fully contained in current branch
  if git merge-base --is-ancestor origin/"$target_branch" origin/"$current_branch"; then
    RESULT="true"
    REASON="target_contained_in_current"
    IS_UP_TO_DATE=true
    echo "RESULT: Target branch is fully contained in current branch" >&2
    echo "::set-output name=is_up_to_date::true" >&2
    echo "::set-output name=reason::target_contained_in_current" >&2
    echo "::notice::Target branch is already contained in current branch" >&2
  else
    # Calculate commits ahead and behind
    BEHIND=$(git rev-list --count origin/"$current_branch"..origin/"$target_branch")
    AHEAD=$(git rev-list --count origin/"$target_branch"..origin/"$current_branch")

    echo "::set-output name=commits_behind::$BEHIND" >&2
    echo "::set-output name=commits_ahead::$AHEAD" >&2

    echo "STATS: Current branch is behind by $BEHIND commits" >&2
    echo "STATS: Current branch is ahead by $AHEAD commits" >&2

    # Show recent commits for debugging (limited to 5)
    echo "::group::Recent Target Branch Commits Not in Current Branch" >&2
    git log --oneline --max-count=5 origin/"$current_branch"..origin/"$target_branch" >&2
    echo "::endgroup::" >&2

    # Special case for main/master branches
    if [[ "$target_branch" == "main" || "$target_branch" == "master" ]]; then
      echo "::group::Special Check for $target_branch Branch" >&2
      
      # Check if a merge would produce any changes
      merge_result=$(git merge-tree "$merge_base" origin/"$target_branch" origin/"$current_branch")
      if [[ ! $merge_result =~ "changed in both" && ! $merge_result =~ "added in" ]]; then
        RESULT="true"
        REASON="no_meaningful_changes"
        IS_UP_TO_DATE=true
        echo "RESULT: Merge check shows no conflicts or meaningful changes needed" >&2
        echo "::set-output name=is_up_to_date::true" >&2
        echo "::set-output name=reason::no_meaningful_changes" >&2
        echo "::notice::No meaningful changes needed despite commit differences" >&2
      fi
      echo "::endgroup::" >&2
    fi

    # --- Final determination if not already determined ---
    if [ "$IS_UP_TO_DATE" != true ]; then
      if [ "$BEHIND" -eq 0 ]; then
        RESULT="true"
        REASON="not_behind"
        echo "RESULT: Branch is up-to-date (not behind target)" >&2
        echo "::set-output name=is_up_to_date::true" >&2
        echo "::set-output name=reason::not_behind" >&2
        echo "::notice::Branch is up-to-date with target" >&2
      else
        RESULT="false"
        REASON="behind_target"
        EXIT_CODE=1
        echo "RESULT: Branch needs updating (behind target by $BEHIND commits)" >&2
        echo "::set-output name=is_up_to_date::false" >&2
        echo "::set-output name=reason::behind_target" >&2
        echo "::warning::Branch is behind target by $BEHIND commits and needs updating" >&2
      fi
    fi
  fi
fi

# Ensure the output group is closed
echo "::endgroup::" >&2

# Output final result (this is what will be captured by command substitution)
echo "$RESULT"

# Set the final GitHub Actions outputs
echo "::set-output name=result::$RESULT" >&2
echo "::set-output name=reason::$REASON" >&2

exit $EXIT_CODE