//! niri frame-loop bridge state, independent of the compositor and transport.
//! The niri adapter feeds *validated* scene events here in dispatch order.
#[derive(Default, Debug)]
pub struct FrameState {
    generation: Option<u64>,
    target: Option<(u64, u32)>,
    pending: Option<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameAction {
    None,
    QueueRedraw,
    Complete(u64),
    Cancel(u64),
}

impl FrameState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Discard references to the old consumer before importing the new set.
    pub fn reset(&mut self, generation: u64) -> FrameAction {
        self.generation = Some(generation);
        self.target = None;
        self.pending
            .take()
            .map_or(FrameAction::None, FrameAction::Cancel)
    }

    pub fn target_ready(&mut self, generation: u64, index: u32, count: u32) -> FrameAction {
        if self.generation != Some(generation) || count == 0 || index >= count {
            return FrameAction::None;
        }
        self.target = Some((generation, index));
        // A selected target is permission to draw, *not* presentation of a frame.
        FrameAction::QueueRedraw
    }

    pub fn target(&self) -> Option<(u64, u32)> {
        if self.pending.is_some() {
            None
        } else {
            self.target
        }
    }

    pub fn submitted(&mut self, generation: u64, index: u32, commit_id: u64) -> bool {
        if commit_id == 0
            || self.pending.is_some()
            || self.target != Some((generation, index))
            || self.generation != Some(generation)
        {
            return false;
        }
        self.target = None;
        self.pending = Some(commit_id);
        true
    }

    pub fn presented(&mut self, commit_id: u64) -> FrameAction {
        if self.pending == Some(commit_id) {
            self.pending = None;
            FrameAction::Complete(commit_id)
        } else {
            FrameAction::None
        }
    }

    pub fn dropped(&mut self, commit_id: u64) -> FrameAction {
        if self.pending == Some(commit_id) {
            self.pending = None;
            FrameAction::Cancel(commit_id)
        } else {
            FrameAction::None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{FrameAction, FrameState};

    #[test]
    fn target_ready_submitted_and_presented() {
        let mut state = FrameState::new();
        assert_eq!(state.reset(7), FrameAction::None);
        assert_eq!(state.target_ready(7, 1, 3), FrameAction::QueueRedraw);
        assert_eq!(state.target(), Some((7, 1)));
        assert!(state.submitted(7, 1, 42));
        assert_eq!(state.target(), None);
        assert_eq!(state.presented(42), FrameAction::Complete(42));
    }

    #[test]
    fn dropped_commit_is_cancelled_once() {
        let mut state = FrameState::new();
        state.reset(1);
        state.target_ready(1, 0, 1);
        assert!(state.submitted(1, 0, 9));
        assert_eq!(state.dropped(9), FrameAction::Cancel(9));
        assert_eq!(state.dropped(9), FrameAction::None);
    }

    #[test]
    fn reset_cancels_pending_and_rejects_stale_targets() {
        let mut state = FrameState::new();
        state.reset(3);
        state.target_ready(3, 0, 1);
        assert!(state.submitted(3, 0, 11));
        assert_eq!(state.reset(4), FrameAction::Cancel(11));
        assert_eq!(state.target_ready(3, 0, 1), FrameAction::None);
        assert_eq!(state.target_ready(4, 1, 1), FrameAction::None);
        assert_eq!(state.target_ready(4, 0, 1), FrameAction::QueueRedraw);
    }

    #[test]
    fn invalid_targets_and_submissions_are_ignored() {
        let mut state = FrameState::new();
        state.reset(2);
        assert_eq!(state.target_ready(2, 0, 0), FrameAction::None);
        assert_eq!(state.target_ready(2, 2, 2), FrameAction::None);
        assert_eq!(state.target_ready(1, 0, 1), FrameAction::None);
        assert!(!state.submitted(2, 0, 1));
    }
}
