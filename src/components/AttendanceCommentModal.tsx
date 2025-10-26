import { useState, useEffect } from 'react';
import { MessageSquare, Send, Trash2 } from 'lucide-react';
import { supabase, AttendanceComment } from '../lib/supabase';
import { Modal } from './ui/Modal';
import { Button } from './ui/Button';
import { Input } from './ui/Input';
import { useToast } from './ui/Toast';
import { useAuth } from '../contexts/AuthContext';

interface AttendanceCommentModalProps {
  isOpen: boolean;
  onClose: () => void;
  employeeName: string;
  workDate: string;
  attendanceRecordId: string | null;
}

export function AttendanceCommentModal({
  isOpen,
  onClose,
  employeeName,
  workDate,
  attendanceRecordId,
}: AttendanceCommentModalProps) {
  const [comments, setComments] = useState<AttendanceComment[]>([]);
  const [newComment, setNewComment] = useState('');
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const { showToast } = useToast();
  const { session } = useAuth();

  useEffect(() => {
    if (isOpen && attendanceRecordId) {
      fetchComments();
    }
  }, [isOpen, attendanceRecordId]);

  async function fetchComments() {
    if (!attendanceRecordId) return;

    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('attendance_comments')
        .select(`
          *,
          employee:employees(id, display_name)
        `)
        .eq('attendance_record_id', attendanceRecordId)
        .order('created_at', { ascending: true });

      if (error) throw error;

      setComments(data || []);
    } catch (error: any) {
      console.error('Error fetching comments:', error);
      showToast('Failed to load comments', 'error');
    } finally {
      setLoading(false);
    }
  }

  async function handleSubmitComment() {
    if (!newComment.trim() || !attendanceRecordId || !session?.employee_id) return;

    try {
      setSubmitting(true);
      const { error } = await supabase
        .from('attendance_comments')
        .insert({
          attendance_record_id: attendanceRecordId,
          employee_id: session.employee_id,
          comment: newComment.trim(),
        });

      if (error) throw error;

      setNewComment('');
      showToast('Comment added successfully', 'success');
      await fetchComments();
    } catch (error: any) {
      console.error('Error adding comment:', error);
      showToast('Failed to add comment', 'error');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDeleteComment(commentId: string) {
    if (!confirm('Are you sure you want to delete this comment?')) return;

    try {
      const { error } = await supabase
        .from('attendance_comments')
        .delete()
        .eq('id', commentId);

      if (error) throw error;

      showToast('Comment deleted successfully', 'success');
      await fetchComments();
    } catch (error: any) {
      console.error('Error deleting comment:', error);
      showToast('Failed to delete comment', 'error');
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Comments - ${employeeName}`}
    >
      <div className="flex items-center gap-2 mb-4">
        <MessageSquare className="w-5 h-5 text-gray-600" />
        <span className="text-sm text-gray-600">Add notes about this attendance record</span>
      </div>
      <div className="space-y-4">
        <div className="text-sm text-gray-600">
          Date: {new Date(workDate).toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
          })}
        </div>

        <div className="border-t border-gray-200 pt-4">
          {loading ? (
            <div className="text-center py-8 text-sm text-gray-500">Loading comments...</div>
          ) : comments.length === 0 ? (
            <div className="text-center py-8">
              <MessageSquare className="w-12 h-12 text-gray-300 mx-auto mb-2" />
              <p className="text-sm text-gray-500">No comments yet</p>
            </div>
          ) : (
            <div className="space-y-3 max-h-96 overflow-y-auto">
              {comments.map((comment) => (
                <div
                  key={comment.id}
                  className="bg-gray-50 rounded-lg p-3 space-y-2"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-semibold text-gray-900">
                          {comment.employee?.display_name || 'Unknown'}
                        </span>
                        <span className="text-xs text-gray-500">
                          {new Date(comment.created_at).toLocaleString('en-US', {
                            month: 'short',
                            day: 'numeric',
                            hour: 'numeric',
                            minute: '2-digit',
                            hour12: true,
                          })}
                        </span>
                      </div>
                      <p className="text-sm text-gray-700">{comment.comment}</p>
                    </div>
                    {session?.employee_id === comment.employee_id && (
                      <button
                        onClick={() => handleDeleteComment(comment.id)}
                        className="text-gray-400 hover:text-red-600 transition-colors"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="border-t border-gray-200 pt-4">
          <div className="flex gap-2">
            <Input
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="Add a comment..."
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  handleSubmitComment();
                }
              }}
              disabled={submitting}
            />
            <Button
              onClick={handleSubmitComment}
              disabled={!newComment.trim() || submitting}
              size="sm"
            >
              <Send className="w-4 h-4" />
            </Button>
          </div>
          <p className="text-xs text-gray-500 mt-2">Press Enter to send</p>
        </div>

        <div className="flex justify-end pt-2">
          <Button variant="secondary" onClick={onClose}>
            Close
          </Button>
        </div>
      </div>
    </Modal>
  );
}
