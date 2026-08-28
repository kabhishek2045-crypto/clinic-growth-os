import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Calendar, Users, HeartPulse, ShieldCheck } from 'lucide-react';

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-b from-background to-muted">
      {/* Hero Section */}
      <section className="container mx-auto px-6 py-24 text-center">
        <h1 className="text-5xl md:text-7xl font-bold tracking-tight">Clinic Growth OS</h1>

        <p className="mt-6 text-xl text-muted-foreground max-w-3xl mx-auto">
          Helping clinics build trust, improve patient understanding, automate operations, and grow
          long-term patient relationships.
        </p>

        <div className="mt-10 flex flex-col sm:flex-row justify-center gap-4">
          <Button size="lg">Book Appointment</Button>

          <Button variant="outline" size="lg">
            Learn More
          </Button>
        </div>
      </section>

      {/* Stats Section */}
      <section className="container mx-auto px-6 pb-20">
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
          <Card>
            <CardContent className="p-6">
              <Users className="mb-4 h-8 w-8" />
              <h3 className="text-3xl font-bold">5000+</h3>
              <p className="text-muted-foreground">Patients Served</p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <Calendar className="mb-4 h-8 w-8" />
              <h3 className="text-3xl font-bold">1200+</h3>
              <p className="text-muted-foreground">Monthly Appointments</p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <HeartPulse className="mb-4 h-8 w-8" />
              <h3 className="text-3xl font-bold">98%</h3>
              <p className="text-muted-foreground">Patient Satisfaction</p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <ShieldCheck className="mb-4 h-8 w-8" />
              <h3 className="text-3xl font-bold">100%</h3>
              <p className="text-muted-foreground">Secure Health Records</p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Features Section */}
      <section className="container mx-auto px-6 py-20">
        <div className="text-center mb-12">
          <h2 className="text-4xl font-bold">Everything Your Clinic Needs</h2>

          <p className="mt-4 text-muted-foreground">
            Run, Grow and Automate your clinic operations.
          </p>
        </div>

        <div className="grid gap-6 md:grid-cols-3">
          <Card>
            <CardContent className="p-6">
              <h3 className="font-semibold text-xl mb-3">Run</h3>

              <p className="text-muted-foreground">
                Manage patients, doctors, appointments, billing, prescriptions and reports.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <h3 className="font-semibold text-xl mb-3">Grow</h3>

              <p className="text-muted-foreground">
                Website, online booking, CRM, WhatsApp follow-ups and patient retention tools.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <h3 className="font-semibold text-xl mb-3">Automate</h3>

              <p className="text-muted-foreground">
                Appointment reminders, follow-up workflows, AI assistance and clinic insights.
              </p>
            </CardContent>
          </Card>
        </div>
      </section>
    </main>
  );
}
