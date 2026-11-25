-- ============================================================================
-- HUDDLE  -  DEVELOPMENT SAMPLE DATA ONLY. Replace with real institution data.
-- Run AFTER schema.sql.
-- ============================================================================
do $$
declare u uuid; c uuid; d_cs uuid; d_ec uuid; f uuid; s1 uuid; s2 uuid; s3 uuid;
begin
  insert into universities (name) values ('Demo State University') returning id into u;
  insert into colleges (university_id, name) values (u, 'College of Engineering') returning id into c;
  insert into departments (college_id, name) values (c, 'Computer Science') returning id into d_cs;
  insert into departments (college_id, name) values (c, 'Electronics') returning id into d_ec;

  insert into subjects (department_id, semester, code, name) values (d_cs, 5, 'CS501', 'Operating Systems') returning id into s1;
  insert into subjects (department_id, semester, code, name) values (d_cs, 5, 'CS502', 'Database Systems') returning id into s2;
  insert into subjects (department_id, semester, code, name) values (d_cs, 5, 'CS503', 'Computer Networks') returning id into s3;

  -- Group hierarchy
  insert into groups (kind, name, description, university_id) values
    ('university', 'Demo State University', 'All students of the university', u);
  insert into groups (kind, name, description, college_id) values
    ('college', 'College of Engineering', 'College-wide chat', c);
  insert into groups (kind, name, description, college_id, department_id) values
    ('department', 'Computer Science', 'CS department', c, d_cs);
  insert into groups (kind, name, description, college_id, department_id, semester) values
    ('semester', 'CS - Semester 5', 'Semester 5 students', c, d_cs, 5);
  insert into groups (kind, name, description, college_id, department_id, semester, batch) values
    ('batch', 'CS Sem 5 - Batch A', 'Class chat', c, d_cs, 5, 'A');
  insert into groups (kind, name, description, subject_id) values
    ('subject', 'Operating Systems', 'CS501 doubts & notes', s1),
    ('subject', 'Database Systems', 'CS502 doubts & notes', s2),
    ('subject', 'Computer Networks', 'CS503 doubts & notes', s3);

  -- A fest with its own announcement + discussion channels
  insert into fests (college_id, university_id, name, tagline, description, starts_on, ends_on, color)
  values (c, u, 'Technova 2027', 'Build. Break. Repeat.',
          'Annual tech fest: hackathon, robo-wars, gaming arena and a night concert.',
          current_date + 40, current_date + 42, '#8B5CF6') returning id into f;
  insert into groups (kind, name, description, fest_id, is_private, announcement_only)
    values ('fest_announce', 'Technova - Announcements', 'Official fest updates', f, false, true);
  insert into groups (kind, name, description, fest_id, is_private)
    values ('fest_chat', 'Technova - Hangout', 'Teams, volunteers, memes', f, false);
end $$;

-- After a teacher signs up in the app, approve them and assign subjects:
--   update profiles set is_authorised = true where username = 'prof.rao';
--   insert into teacher_assignments (teacher_id, subject_id, class_label)
--     select p.id, s.id, 'CS Sem 5 - Batch A' from profiles p, subjects s
--      where p.username = 'prof.rao' and s.code in ('CS501','CS502');
-- To create an institutional (official-notice) account: sign it up as a student,
-- then: update profiles set role = 'institution', is_authorised = true where username = 'registrar';
-- To make someone a fest organiser (can post in announcements):
--   update group_members set role = 'admin' where user_id = (select id from profiles where username = '...')
--     and group_id in (select id from groups where kind = 'fest_announce');
