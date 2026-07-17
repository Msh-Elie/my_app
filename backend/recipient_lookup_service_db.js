// Outil autonome local (facultatif) pour administrer la base de bénéficiaires
// hors du process principal : ajouter/supprimer des entrées, consulter les
// stats. Le backend (server.js) n'en a plus besoin pour fonctionner — il
// utilise directement recipient_lookup.js en interne (voir /api/resolve-recipient).
// À ne PAS déployer publiquement : les routes d'écriture ne sont pas protégées.
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '.env') });

const { recipientLookupRouter } = await import('./recipient_lookup.js');

const app = express();
app.use(cors());
app.use(express.json());
app.use('/', recipientLookupRouter);

const PORT = process.env.RECIPIENT_LOOKUP_PORT || 3003;
app.listen(PORT, () => {
  console.log(`\n🔍 Outil admin bénéficiaires (local uniquement) sur http://localhost:${PORT}`);
  console.log(`   GET    /health`);
  console.log(`   POST   /lookup`);
  console.log(`   GET    /recipients`);
  console.log(`   POST   /recipients`);
  console.log(`   DELETE /recipients/:phone`);
  console.log(`   GET    /stats\n`);
});
