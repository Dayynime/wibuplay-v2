-- Bucket gambar pengganti Cloudinary. Upload hanya lewat signed URL dari
-- Edge Function media-upload (service role); publik hanya bisa membaca.
begin;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clan-media', 'clan-media', true, 10485760,
        array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

update storage.buckets
   set public = true, file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif']
 where id in ('chat-avatars', 'chat-banners');

select id, public, file_size_limit, allowed_mime_types from storage.buckets
 where id in ('chat-avatars', 'chat-banners', 'clan-media');
commit;
